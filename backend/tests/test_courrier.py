import io

import pytest
from pypdf import PdfWriter

from pli.courrier import Courrier, FormatNonLisible, nombre_de_pages, texte_du_courrier


def _pdf(mot_de_passe: str | None = None) -> bytes:
    ecrivain = PdfWriter()
    ecrivain.add_blank_page(width=200, height=200)
    if mot_de_passe:
        ecrivain.encrypt(mot_de_passe)
    sortie = io.BytesIO()
    ecrivain.write(sortie)
    return sortie.getvalue()


def test_password_protected_pdf_is_unreadable_not_a_crash():
    with pytest.raises(FormatNonLisible, match="mot de passe"):
        texte_du_courrier(Courrier(media_type="application/pdf", contenu=_pdf("secret")))


def test_pdf_without_text_asks_for_the_photo_path():
    with pytest.raises(FormatNonLisible, match="scan"):
        texte_du_courrier(Courrier(media_type="application/pdf", contenu=_pdf()))


def test_garbage_is_not_a_pdf():
    with pytest.raises(FormatNonLisible):
        texte_du_courrier(Courrier(media_type="application/pdf", contenu=b"pas un pdf"))


def test_counts_the_pages_of_a_pdf():
    assert nombre_de_pages(_pdf()) == 1


@pytest.mark.parametrize("contenu", [b"", b"pas un pdf", b"%PDF-1.7 coupe au milieu"])
def test_page_count_of_a_broken_pdf_is_unreadable_not_a_crash(contenu):
    with pytest.raises(FormatNonLisible):
        nombre_de_pages(contenu)


def test_page_count_of_a_password_protected_pdf_is_unreadable():
    with pytest.raises(FormatNonLisible):
        nombre_de_pages(_pdf(mot_de_passe="secret"))
