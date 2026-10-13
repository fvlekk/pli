from datetime import date

import pytest
from fastapi.testclient import TestClient

from pli.auth import AuthIndisponible, JetonInvalide
from pli.config import Config
from pli.extracteurs.base import Resultat
from pli.main import creer_app
from pli.schema import Extraction

AUJOURDHUI = date(2026, 10, 12)


def extraction(**champs) -> Extraction:
    valeurs = {
        "organisme": "impots",
        "organisme_nom": "Finances publiques",
        "action": "payer",
        "titre": "Payer l'impôt",
        "date_limite": date(2026, 11, 15),
        "montant": 120.0,
        "date_courrier": date(2026, 10, 1),
        "resume": "Tu dois payer 120 € avant le 15 novembre.",
        "a_verifier": False,
        "raison_verification": None,
    }
    return Extraction(**{**valeurs, **champs})


class FauxVerificateur:
    def uid(self, jeton: str) -> str:
        if jeton == "panne":
            raise AuthIndisponible("CertificateFetchError")
        if not jeton.startswith("ok-"):
            raise JetonInvalide("faux jeton")
        return jeton.removeprefix("ok-")


class FauxExtracteur:
    nom = "faux"

    def __init__(self):
        self.appels = []
        self.erreur: Exception | None = None

    def extraire(self, courrier, recu_le):
        self.appels.append((courrier, recu_le))
        if self.erreur:
            raise self.erreur
        return Resultat(
            extraction=extraction(), source="faux", modele="faux-1", jetons_entree=10, jetons_sortie=5
        )


def config(**champs) -> Config:
    valeurs = {
        "extracteur": "regle",
        "modele": "claude-opus-5-5",
        "effort": "medium",
        "origines_cors": ("http://localhost:5173",),
        "requetes_par_minute": 3,
        "requetes_par_minute_instance": 100,
        "taille_max_octets": 1000,
        "auth_emulateur": False,
        "projet_firebase": None,
    }
    return Config(**{**valeurs, **champs})


@pytest.fixture
def extracteur() -> FauxExtracteur:
    return FauxExtracteur()


@pytest.fixture
def client(extracteur) -> TestClient:
    app = creer_app(config(), extracteur, FauxVerificateur(), aujourdhui=lambda: AUJOURDHUI)
    return TestClient(app)


AUTH = {"Authorization": "Bearer ok-alice"}
