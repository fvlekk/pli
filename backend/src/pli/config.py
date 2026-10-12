"""Settings, all from environment variables (Cloud Run sets them; secrets come from Secret Manager)."""

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
    taille_max_octets: int
    auth_emulateur: bool
    projet_firebase: str | None

    @classmethod
    def depuis_env(cls) -> "Config":
        env = os.environ
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
            taille_max_octets=int(env.get("PLI_TAILLE_MAX_OCTETS", str(5 * 1024 * 1024))),
            auth_emulateur=env.get("PLI_AUTH_EMULATEUR") == "1",
            projet_firebase=env.get("PLI_PROJET_FIREBASE") or env.get("GOOGLE_CLOUD_PROJECT"),
        )
