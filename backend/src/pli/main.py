"""HTTP API. Run with: uv run uvicorn --factory pli.main:creer_app_depuis_env --port 8080"""

import asyncio
import base64
import binascii
import gc
import os
import threading
import time
from collections.abc import Callable, Iterator
from datetime import date, datetime
from typing import Annotated, Literal
from zoneinfo import ZoneInfo

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field, ValidationError, model_validator
from starlette.requests import ClientDisconnect

from pli.auth import AuthIndisponible, JetonInvalide, VerificateurFirebase, VerificateurJeton
from pli.config import Config
from pli.courrier import Courrier, FormatNonLisible, nombre_de_pages, type_image
from pli.extracteurs.base import Extracteur
from pli.extracteurs.claude import ExtracteurClaude, ExtractionImpossible, ServiceIndisponible
from pli.extracteurs.regle import ExtracteurRegle
from pli.journal import journaliser, uid_masque
from pli.limiteur import Limiteur
from pli.schema import Extraction

PARIS = ZoneInfo("Europe/Paris")
ATTENTE_CORPS = 120  # seconds: a client that stops sending must not keep its reading place


class Fichier(BaseModel):
    media_type: Literal["application/pdf", "image/png", "image/jpeg", "image/webp"]
    donnees_base64: str


class DemandeExtraction(BaseModel):
    texte: str | None = Field(default=None, max_length=50_000)
    fichier: Fichier | None = None
    # The phone's local date: "within 15 days of receipt" counts from the user's day, not Paris's.
    recu_le: date | None = None

    @model_validator(mode="after")
    def _un_seul(self) -> "DemandeExtraction":
        if (self.texte is None) == (self.fichier is None):
            raise ValueError("envoie soit `texte`, soit `fichier`")
        if self.texte is not None and not self.texte.strip():
            raise ValueError("le texte est vide")
        return self


class ReponseExtraction(BaseModel):
    extraction: Extraction
    source: str
    modele: str | None


def date_de_reception(annoncee: date | None, aujourdhui: date) -> date:
    """The client's date if it is within a day of ours (time zones), ours otherwise."""
    if annoncee is None or abs((annoncee - aujourdhui).days) > 1:
        return aujourdhui
    return annoncee


def aujourdhui_paris() -> date:
    return datetime.now(PARIS).date()


def creer_app(
    config: Config,
    extracteur: Extracteur,
    verificateur: VerificateurJeton,
    aujourdhui: Callable[[], date] = aujourdhui_paris,
) -> FastAPI:
    app = FastAPI(title="Pli", docs_url=None, redoc_url=None, openapi_url=None)
    limiteur = Limiteur(
        config.requetes_par_minute,
        config.requetes_par_minute_instance,
        config.requetes_par_jour,
        config.requetes_par_jour_instance,
    )
    taille_max_requete = config.taille_max_octets * 4 // 3 + 4096  # base64 + JSON envelope
    places = threading.BoundedSemaphore(config.lectures_simultanees)

    @app.middleware("http")
    async def entetes_et_taille(request: Request, call_next):
        if request.method == "POST":
            longueur = request.headers.get("content-length")
            if longueur is None:
                return JSONResponse({"detail": "Content-Length requis"}, status_code=411)
            if not longueur.isdigit() or int(longueur) > taille_max_requete:
                return JSONResponse({"detail": "Fichier trop lourd (5 Mo maximum)"}, status_code=413)
        reponse = await call_next(request)
        reponse.headers["X-Content-Type-Options"] = "nosniff"
        reponse.headers["Referrer-Policy"] = "no-referrer"
        reponse.headers["X-Frame-Options"] = "DENY"
        reponse.headers["Cache-Control"] = "no-store"
        return reponse

    # Added last so it wraps everything: 411/413/429 answers keep their CORS headers.
    app.add_middleware(
        CORSMiddleware,
        allow_origins=list(config.origines_cors),
        allow_methods=["GET", "POST"],
        allow_headers=["Authorization", "Content-Type", "X-Firebase-AppCheck"],
        max_age=600,
    )

    def application(request: Request) -> str:
        """« ok », « absent », « invalide » or « indisponible ». Blocks only when App Check is required."""
        jeton = request.headers.get("x-firebase-appcheck", "").strip()
        if not jeton:
            statut = "absent"
        else:
            try:
                verificateur.app_check(jeton)
                statut = "ok"
            except JetonInvalide:
                statut = "invalide"
            except AuthIndisponible:
                statut = "indisponible"
        if config.app_check_obligatoire and statut != "ok":
            if statut == "indisponible":
                raise HTTPException(
                    503, "Vérification impossible pour le moment, réessaie", {"Retry-After": "30"}
                )
            raise HTTPException(401, "Application non reconnue : ferme et rouvre Pli, puis réessaie")
        return statut

    def utilisateur(request: Request) -> str:
        request.state.app_check = application(request)
        entete = request.headers.get("authorization", "")
        if not entete.lower().startswith("bearer "):
            raise HTTPException(401, "Connexion requise")
        try:
            uid = verificateur.uid(entete[7:].strip())
        except JetonInvalide:
            raise HTTPException(401, "Connexion expirée, reconnecte-toi") from None
        except AuthIndisponible:
            raise HTTPException(
                503, "Connexion impossible pour le moment, réessaie", {"Retry-After": "30"}
            ) from None
        if not limiteur.autoriser(uid):
            raise HTTPException(
                429, "Trop de courriers d'un coup, réessaie dans une minute", {"Retry-After": "60"}
            )
        return uid

    def place_de_lecture(uid: str = Depends(utilisateur)) -> Iterator[None]:
        """Limits per minute do not bound what is in memory at once: a reading can last two minutes."""
        if not places.acquire(blocking=False):
            raise HTTPException(503, "Le service de lecture est occupé, réessaie", {"Retry-After": "30"})
        try:
            yield
        finally:
            # A failed call leaves the letter in reference cycles: left to the next full collection, a few
            # junk images were enough to pass 512 MB.
            gc.collect()
            places.release()

    async def demande_lue(request: Request, _place: None = Depends(place_de_lecture)) -> DemandeExtraction:
        """The body, read only once the caller is known and within its limit: at up to 7 MB a request, scripts
        without a token could otherwise fill a small instance's memory. A refusal never echoes the letter."""
        try:
            async with asyncio.timeout(ATTENTE_CORPS):
                return DemandeExtraction.model_validate_json(await request.body())
        except TimeoutError:
            raise HTTPException(408, "Envoi trop lent : vérifie ta connexion et réessaie") from None
        except ClientDisconnect:
            raise HTTPException(400, "Envoi interrompu") from None
        except ValidationError:
            raise HTTPException(422, "Ce courrier n'est pas lisible : vérifie ce que tu as envoyé") from None

    @app.get("/healthz")
    def sante() -> dict:
        return {"ok": True, "extracteur": extracteur.nom}

    @app.post("/v1/extractions")
    def extraire(
        request: Request,
        demande: Annotated[DemandeExtraction, Depends(demande_lue)],
        uid: str = Depends(utilisateur),
    ) -> ReponseExtraction:
        if demande.fichier:
            try:
                contenu = base64.b64decode(demande.fichier.donnees_base64, validate=True)
            except (binascii.Error, ValueError):
                raise HTTPException(422, "Fichier mal encodé") from None
            if len(contenu) > config.taille_max_octets:
                raise HTTPException(413, "Fichier trop lourd (5 Mo maximum)")
            media_type = demande.fichier.media_type
            if media_type == "application/pdf":
                try:
                    pages = nombre_de_pages(contenu)
                except FormatNonLisible as e:
                    raise HTTPException(422, f"Je ne sais pas lire ce courrier : {e}") from None
                if pages > config.pages_max:
                    raise HTTPException(
                        422,
                        f"PDF trop long ({config.pages_max} pages maximum) : garde les pages utiles",
                    )
            else:
                media_type = type_image(contenu)
                if media_type is None:
                    raise HTTPException(
                        422, "Cette image n'est pas lisible : envoie un PNG, un JPEG ou un WebP"
                    )
            courrier = Courrier(media_type=media_type, contenu=contenu)
        else:
            courrier = Courrier(texte=demande.texte)

        # Charged here: a request refused above never reaches the model, so it costs no quota.
        if not limiteur.autoriser_aujourdhui(uid):
            raise HTTPException(429, "Limite du jour atteinte, réessaie demain", {"Retry-After": "3600"})

        debut = time.perf_counter()
        trace = {
            "uid": uid_masque(uid),
            "extracteur": extracteur.nom,
            "media_type": courrier.media_type or "text",
            "app_check": request.state.app_check,
        }
        try:
            resultat = extracteur.extraire(courrier, date_de_reception(demande.recu_le, aujourdhui()))
        except FormatNonLisible as e:
            raise HTTPException(422, f"Je ne sais pas lire ce courrier : {e}") from None
        except ServiceIndisponible as e:
            journaliser("extraction indisponible", "WARNING", raison=str(e), **trace)
            raise HTTPException(
                503, "Le service de lecture est occupé, réessaie", {"Retry-After": "30"}
            ) from None
        except ExtractionImpossible as e:
            journaliser("extraction impossible", "ERROR", raison=str(e), **trace)
            raise HTTPException(502, "Lecture impossible : saisis l'échéance à la main") from None

        journaliser(
            "extraction",
            duree_ms=round(1000 * (time.perf_counter() - debut)),
            modele=resultat.modele,
            jetons_entree=resultat.jetons_entree,
            jetons_sortie=resultat.jetons_sortie,
            a_verifier=resultat.extraction.a_verifier,
            **trace,
        )
        return ReponseExtraction(
            extraction=resultat.extraction, source=resultat.source, modele=resultat.modele
        )

    return app


def creer_app_depuis_env() -> FastAPI:
    config = Config.depuis_env()
    emulateur = bool(os.environ.get("FIREBASE_AUTH_EMULATOR_HOST"))
    if emulateur and (not config.auth_emulateur or os.environ.get("K_SERVICE") or os.environ.get("RENDER")):
        # The emulator makes firebase-admin accept unsigned tokens: refuse rather than run wide open.
        raise RuntimeError("FIREBASE_AUTH_EMULATOR_HOST est défini hors du mode émulateur local")
    if not emulateur:
        # Both are normal locally. On a host, a lost variable must not degrade in silence.
        if not config.app_check_obligatoire:
            journaliser("App Check n'est pas obligatoire (PLI_APP_CHECK)", "WARNING")
        if config.extracteur != "claude":
            journaliser("extracteur de secours sans Claude (ANTHROPIC_API_KEY)", "WARNING")
    extracteur = (
        ExtracteurClaude.depuis_config(config) if config.extracteur == "claude" else ExtracteurRegle()
    )
    projet = config.projet_firebase or ("demo-pli" if emulateur else None)
    return creer_app(config, extracteur, VerificateurFirebase(projet))
