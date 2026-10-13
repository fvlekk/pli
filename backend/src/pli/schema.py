"""The extraction contract shared by both extractors, the API, the eval and the app."""

from datetime import date
from typing import Literal

from pydantic import BaseModel, Field, field_validator

Organisme = Literal[
    "impots",
    "caf",
    "assurance_maladie",
    "urssaf",
    "france_travail",
    "prefecture",
    "antai",
    "crous",
    "ants",
    "mutuelle",
    "assurance",
    "energie",
    "bailleur",
    "autre",
]

Action = Literal[
    "payer",
    "declarer",
    "envoyer_documents",
    "renouveler",
    "se_presenter",
    "demander",
    "repondre",
    "aucune",
]

MONTANT_MAX = 1_000_000


class Extraction(BaseModel):
    """What the user must do, for whom, by when, and for how much."""

    organisme: Organisme = Field(description="Catégorie de l'organisme qui a envoyé le courrier.")
    organisme_nom: str = Field(description="Nom de l'organisme tel qu'écrit dans le courrier.")
    action: Action = Field(description="La démarche principale demandée au destinataire.")
    titre: str = Field(description="Titre court à l'infinitif, ex. « Payer l'impôt sur le revenu ».")
    date_limite: date | None = Field(
        description="Dernier jour pour faire la démarche (AAAA-MM-JJ). Null s'il n'y a aucune démarche datée."
    )
    montant: float | None = Field(description="Somme en euros à payer pour faire la démarche, sinon null.")
    date_courrier: date | None = Field(description="Date du courrier ou de son envoi, si elle est écrite.")
    resume: str = Field(description="Une ou deux phrases simples, en tutoyant, sur ce qu'il faut faire.")
    a_verifier: bool = Field(description="Vrai si le courrier est ambigu ou si une valeur est incertaine.")
    raison_verification: str | None = Field(description="Ce qui est incertain, si a_verifier est vrai.")

    @field_validator("montant")
    @classmethod
    def _montant_plausible(cls, v: float | None) -> float | None:
        if v is None:
            return None
        if v < 0 or v >= MONTANT_MAX:
            raise ValueError("montant hors limites")
        return round(v, 2)

    # Same limits as firestore.rules, or the app could not save what the backend returned.
    @field_validator("titre", "organisme_nom")
    @classmethod
    def _court(cls, v: str) -> str:
        return v.strip()[:120]

    @field_validator("resume")
    @classmethod
    def _resume_borne(cls, v: str) -> str:
        return v.strip()[:500]


def verifier_coherence(extraction: Extraction, recu_le: date) -> Extraction:
    """Flags values that are possible but suspicious, so the app asks the user to check them."""
    raisons = []
    if extraction.date_limite and extraction.date_limite < recu_le:
        raisons.append("la date limite est déjà passée")
    if extraction.date_limite and (extraction.date_limite - recu_le).days > 3 * 365:
        raisons.append("la date limite est à plus de trois ans")
    if extraction.action == "payer" and extraction.montant is None:
        raisons.append("aucun montant trouvé pour un paiement")
    if extraction.action != "aucune" and extraction.date_limite is None:
        raisons.append("aucune date limite trouvée")
    if not raisons:
        return extraction
    existantes = [extraction.raison_verification] if extraction.raison_verification else []
    return extraction.model_copy(
        update={"a_verifier": True, "raison_verification": " ; ".join(existantes + raisons)}
    )
