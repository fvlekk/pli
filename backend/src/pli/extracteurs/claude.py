"""Claude extractor: reads text, PDF or photo and returns an `Extraction` validated by pydantic."""

import base64
import re
from datetime import date
from pathlib import Path

import anthropic
from pydantic import ValidationError

from pli.config import Config
from pli.courrier import Courrier
from pli.extracteurs.base import Resultat
from pli.schema import Extraction, verifier_coherence

# Versioned with the code: any change to it comes with an eval run (see CLAUDE.md).
SYSTEME = (Path(__file__).parent / "consigne.md").read_text(encoding="utf-8")


BALISE = re.compile(r"<\s*/?\s*courrier[^>]*>", re.IGNORECASE)


def neutraliser(texte: str) -> str:
    """Removes every form of the <courrier> tag, until none is left (nested tricks included)."""
    while True:
        propre = BALISE.sub("", texte)
        if propre == texte:
            return propre
        texte = propre


class ExtractionImpossible(Exception):
    """The model answered but gave no usable extraction (refusal, truncated output)."""


class ServiceIndisponible(Exception):
    """The API is unreachable or overloaded; the caller may retry later."""


class ExtracteurClaude:
    nom = "claude"

    def __init__(self, client: anthropic.Anthropic, modele: str, effort: str):
        self.client = client
        self.modele = modele
        self.effort = effort

    @classmethod
    def depuis_config(cls, config: Config) -> "ExtracteurClaude":
        # The client reads ANTHROPIC_API_KEY from the environment; the key never goes through our code.
        return cls(anthropic.Anthropic(max_retries=2, timeout=60), config.modele, config.effort)

    def _contenu(self, courrier: Courrier, recu_le: date) -> list[dict]:
        consigne = f"Courrier reçu le {recu_le.isoformat()}."
        if courrier.texte is not None:
            texte = neutraliser(courrier.texte)
            return [{"type": "text", "text": f"{consigne}\n\n<courrier>\n{texte}\n</courrier>"}]
        donnees = base64.standard_b64encode(courrier.contenu or b"").decode("ascii")
        source = {"type": "base64", "media_type": courrier.media_type, "data": donnees}
        bloc = {"type": "image" if courrier.est_image else "document", "source": source}
        return [bloc, {"type": "text", "text": f"{consigne} Le courrier est le document joint."}]

    def extraire(self, courrier: Courrier, recu_le: date) -> Resultat:
        try:
            reponse = self.client.beta.messages.parse(
                model=self.modele,
                max_tokens=16000,
                betas=["server-side-fallback-2026-07-01"],
                fallbacks="default",
                output_config={"effort": self.effort},
                output_format=Extraction,
                system=[{"type": "text", "text": SYSTEME, "cache_control": {"type": "ephemeral"}}],
                messages=[{"role": "user", "content": self._contenu(courrier, recu_le)}],
            )
        except (
            anthropic.RateLimitError,
            anthropic.OverloadedError,
            anthropic.ServiceUnavailableError,
            anthropic.InternalServerError,
            anthropic.APIConnectionError,
        ) as e:
            raise ServiceIndisponible(type(e).__name__) from e
        except anthropic.APIStatusError as e:
            raise ExtractionImpossible(f"API {e.status_code}") from e
        except ValidationError:
            # The SDK validates the JSON against the schema (truncated output, amount out of bounds...).
            # `from None` and no message: the error text quotes the model's output, which quotes the letter.
            raise ExtractionImpossible("sortie invalide") from None

        if reponse.stop_reason != "end_turn" or reponse.parsed_output is None:
            raise ExtractionImpossible(f"stop_reason={reponse.stop_reason}")
        return Resultat(
            extraction=verifier_coherence(reponse.parsed_output, recu_le),
            source=self.nom,
            modele=reponse.model,
            jetons_entree=reponse.usage.input_tokens,
            jetons_sortie=reponse.usage.output_tokens,
        )
