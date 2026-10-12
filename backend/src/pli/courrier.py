"""A letter as the user sends it: pasted text, a PDF or a photo."""

import io
from dataclasses import dataclass

from pypdf import PdfReader
from pypdf.errors import PdfReadError

FORMATS_FICHIER = {"application/pdf", "image/png", "image/jpeg", "image/webp"}


class FormatNonLisible(Exception):
    """The extractor cannot read this kind of document."""


@dataclass(frozen=True)
class Courrier:
    texte: str | None = None
    media_type: str | None = None
    contenu: bytes | None = None

    @property
    def est_image(self) -> bool:
        return bool(self.media_type and self.media_type.startswith("image/"))


def texte_du_courrier(courrier: Courrier) -> str:
    """Plain text of the letter, for extractors that only read text."""
    if courrier.texte is not None:
        return courrier.texte
    if courrier.media_type == "application/pdf" and courrier.contenu:
        try:
            pages = PdfReader(io.BytesIO(courrier.contenu)).pages
            texte = "\n".join(page.extract_text() or "" for page in pages)
        except PdfReadError as e:  # includes FileNotDecryptedError (password-protected PDF)
            raise FormatNonLisible("PDF illisible ou protégé par un mot de passe") from e
        if not texte.strip():
            raise FormatNonLisible("PDF sans texte (scan) : il faut le lire comme une image")
        return texte
    raise FormatNonLisible("photo : seul l'extracteur Claude sait lire une image")
