"""A letter as the user sends it: pasted text, a PDF or a photo."""

import io
import threading
from dataclasses import dataclass

from pypdf import PdfReader


class FormatNonLisible(Exception):
    """The extractor cannot read this kind of document."""


# Parsing a large crafted PDF takes over 100 MB for a second or two: one at a time, on a small instance.
_analyse_pdf = threading.Lock()


def nombre_de_pages(pdf: bytes) -> int:
    """Pages of a PDF sent by a user, checked before any extractor reads it."""
    try:
        with _analyse_pdf:
            return len(PdfReader(io.BytesIO(pdf)).pages)
    except Exception as e:  # untrusted bytes: pypdf raises many kinds of errors on a broken file
        raise FormatNonLisible("PDF illisible ou protégé par un mot de passe") from e


def type_image(contenu: bytes) -> str | None:
    """The image's real type, from its first bytes. None if it is none of the formats we accept."""
    if contenu.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if contenu.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if contenu[:4] == b"RIFF" and contenu[8:12] == b"WEBP":
        return "image/webp"
    return None


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
        except Exception as e:  # untrusted bytes, as in nombre_de_pages (password-protected PDF included)
            raise FormatNonLisible("PDF illisible ou protégé par un mot de passe") from e
        if not texte.strip():
            raise FormatNonLisible("PDF sans texte (scan) : il faut le lire comme une image")
        return texte
    raise FormatNonLisible("photo : seul l'extracteur Claude sait lire une image")
