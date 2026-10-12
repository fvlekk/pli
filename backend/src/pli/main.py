"""HTTP API. Run with: uv run uvicorn --factory pli.main:creer_app_depuis_env --port 8080"""

import base64
import binascii
import os
import time
from collections.abc import Callable
from datetime import date, datetime
from typing import Literal
from zoneinfo import ZoneInfo

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field, model_validator

from pli.auth import AuthIndisponible, JetonInvalide, VerificateurFirebase, VerificateurJeton
from pli.config import Config
from pli.courrier import Courrier, FormatNonLisible
from pli.extracteurs.base import Extracteur
from pli.extracteurs.claude import ExtracteurClaude, ExtractionImpossible, ServiceIndisponible
from pli.extracteurs.regle import ExtracteurRegle
from pli.journal import journaliser, uid_masque
from pli.limiteur import Limiteur
from pli.schema import Extraction

PARIS = ZoneInfo("Europe/Paris")


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
    limiteur = Limiteur(config.requetes_par_minute, config.requetes_par_minute_instance)
    taille_max_requete = config.taille_max_octets * 4 // 3 + 4096  # base64 + JSON envelope

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
        allow_headers=["Authorization", "Content-Type"],
        max_age=600,
    )

    def utilisateur(request: Request) -> str:
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

    @app.get("/healthz")
    def sante() -> dict:
        return {"ok": True, "extracteur": extracteur.nom}

    @app.post("/v1/extractions")
    def extraire(demande: DemandeExtraction, uid: str = Depends(utilisateur)) -> ReponseExtraction:
        if demande.fichier:
            try:
                contenu = base64.b64decode(demande.fichier.donnees_base64, validate=True)
            except (binascii.Error, ValueError):
                raise HTTPException(422, "Fichier mal encodé") from None
            if len(contenu) > config.taille_max_octets:
                raise HTTPException(413, "Fichier trop lourd (5 Mo maximum)")
            courrier = Courrier(media_type=demande.fichier.media_type, contenu=contenu)
        else:
            courrier = Courrier(texte=demande.texte)

        debut = time.perf_counter()
        trace = {
            "uid": uid_masque(uid),
            "extracteur": extracteur.nom,
            "media_type": courrier.media_type or "text",
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
    if emulateur and (not config.auth_emulateur or os.environ.get("K_SERVICE")):
        # The emulator makes firebase-admin accept unsigned tokens: refuse rather than run wide open.
        raise RuntimeError("FIREBASE_AUTH_EMULATOR_HOST est défini hors du mode émulateur local")
    extracteur = (
        ExtracteurClaude.depuis_config(config) if config.extracteur == "claude" else ExtracteurRegle()
    )
    projet = config.projet_firebase or ("demo-pli" if emulateur else None)
    return creer_app(config, extracteur, VerificateurFirebase(projet))
