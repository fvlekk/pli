from datetime import date

import pytest

from pli.courrier import Courrier, FormatNonLisible
from pli.extracteurs.regle import ExtracteurRegle, date_du_courrier, date_limite, montant, organisme

BASE = date(2026, 10, 1)


@pytest.mark.parametrize(
    ("texte", "attendu"),
    [
        ("Date limite de paiement : 15/09/2026", date(2026, 9, 15)),
        ("à faire avant le 5 novembre 2026 sur caf.fr", date(2026, 11, 5)),
        ("au plus tard le 1er décembre 2026", date(2026, 12, 1)),
        ("Vous êtes convoqué le mercredi 21 octobre 2026 à 9 h 30", date(2026, 10, 21)),
        ("à nous transmettre sous 15 jours à compter de la date du présent courrier", date(2026, 10, 16)),
        ("Merci pour votre confiance.", None),
    ],
)
def test_date_limite(texte, attendu):
    assert date_limite(texte, BASE) == attendu


def test_date_du_courrier():
    assert date_du_courrier("Paris, le 6 octobre 2026\nObjet") == date(2026, 10, 6)
    assert date_du_courrier("Date d'envoi de l'avis : 03/10/2026") == date(2026, 10, 3)


def test_montant_prefers_the_amount_left_to_pay():
    texte = "Impôt net : 1 896,00 €\nDéjà versé : 648,00 €\nMontant restant à payer : 1 248,00 €"
    assert montant(texte) == 1248.0


def test_organisme_reads_the_letterhead_first():
    assert (
        organisme("AGENCE IMMOBILIÈRE DU PARC\nGestion locative\n\nVotre assurance habitation") == "bailleur"
    )
    assert organisme("l'Assurance Maladie\nCPAM") == "assurance_maladie"


def test_information_letters_have_no_deadline_nor_amount():
    resultat = ExtracteurRegle().extraire(
        Courrier(texte="Le 2 octobre 2026\nVotre aide passe à 245,12 €. Aucune démarche n'est nécessaire."),
        BASE,
    )
    assert resultat.extraction.action == "aucune"
    assert resultat.extraction.date_limite is None
    assert resultat.extraction.montant is None


def test_missing_deadline_is_flagged_not_guessed():
    resultat = ExtracteurRegle().extraire(
        Courrier(texte="Urssaf\nMerci de régler 286,00 € rapidement."), BASE
    )
    assert resultat.extraction.date_limite is None
    assert resultat.extraction.a_verifier


def test_photos_need_the_model():
    with pytest.raises(FormatNonLisible):
        ExtracteurRegle().extraire(Courrier(media_type="image/png", contenu=b"png"), BASE)
