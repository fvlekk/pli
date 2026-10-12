from dataclasses import dataclass
from datetime import date
from typing import Protocol

from pli.courrier import Courrier
from pli.schema import Extraction


@dataclass(frozen=True)
class Resultat:
    extraction: Extraction
    source: str
    modele: str | None = None
    jetons_entree: int | None = None
    jetons_sortie: int | None = None


class Extracteur(Protocol):
    nom: str

    def extraire(self, courrier: Courrier, recu_le: date) -> Resultat: ...
