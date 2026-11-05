"""Settings, all from environment variables set on the host (Render today), secrets included."""

import os
from dataclasses import dataclass


def _liste(valeur: str) -> tuple[str, ...]:
    return tuple(v.strip() for v in valeur.split(",") if v.strip())


@dataclass(frozen=True)
class Config:
    extracteur: str
    modele: str
    effort: str
    origines_cors: tuple[str, ...]
    requetes_par_minute: int
    requetes_par_minute_instance: int
    requetes_par_jour: int
    requetes_par_jour_instance: int
    lectures_simultanees: int
    taille_max_octets: int
    pages_max: int
    app_check_obligatoire: bool
    auth_emulateur: bool
    projet_firebase: str | None

    @classmethod
    def depuis_env(cls) -> "Config":
        env = os.environ
        auth_emulateur = env.get("PLI_AUTH_EMULATEUR") == "1"
        extracteur = env.get("PLI_EXTRACTEUR", "auto")
        if extracteur == "auto":
            # Claude when a key is configured, the rule extractor otherwise.
            cle_presente = bool(env.get("ANTHROPIC_API_KEY") or env.get("ANTHROPIC_AUTH_TOKEN"))
            extracteur = "claude" if cle_presente else "regle"
        return cls(
            extracteur=extracteur,
            modele=env.get("PLI_MODELE", "claude-opus-5-5"),
            effort=env.get("PLI_EFFORT", "medium"),
            origines_cors=_liste(env.get("PLI_ORIGINES_CORS", "http://localhost:5173,http://127.0.0.1:5173")),
            requetes_par_minute=int(env.get("PLI_REQUETES_PAR_MINUTE", "10")),
            requetes_par_minute_instance=int(env.get("PLI_REQUETES_PAR_MINUTE_INSTANCE", "60")),
            requetes_par_jour=int(env.get("PLI_REQUETES_PAR_JOUR", "30")),
            requetes_par_jour_instance=int(env.get("PLI_REQUETES_PAR_JOUR_INSTANCE", "500")),
            # Each reading in progress holds about 75 MB (a 5 MB file, in several forms) on a 512 MB instance.
            lectures_simultanees=int(env.get("PLI_LECTURES_SIMULTANEES", "4")),
            taille_max_octets=int(env.get("PLI_TAILLE_MAX_OCTETS", str(5 * 1024 * 1024))),
            # A letter is a few pages; a long PDF would multiply the cost of one Claude call.
            pages_max=int(env.get("PLI_PAGES_MAX", "10")),
            # Required unless told otherwise: losing this variable on a host must not open the paid route.
            # Off (PLI_APP_CHECK=0, or the local emulator): tokens are only checked and logged.
            app_check_obligatoire=env.get("PLI_APP_CHECK", "0" if auth_emulateur else "1") == "1",
            auth_emulateur=auth_emulateur,
            projet_firebase=env.get("PLI_PROJET_FIREBASE") or env.get("GOOGLE_CLOUD_PROJECT"),
        )
