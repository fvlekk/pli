from datetime import date

import pytest
from pydantic import ValidationError

from pli.schema import verifier_coherence

from .conftest import extraction

RECU_LE = date(2026, 10, 12)


def test_coherent_extraction_is_left_alone():
    e = extraction()
    assert verifier_coherence(e, RECU_LE) == e


@pytest.mark.parametrize(
    ("champs", "raison"),
    [
        ({"date_limite": date(2026, 10, 1)}, "déjà passée"),
        ({"date_limite": date(2031, 1, 1)}, "plus de trois ans"),
        ({"montant": None}, "aucun montant"),
        ({"date_limite": None}, "aucune date"),
    ],
)
def test_suspicious_values_are_flagged(champs, raison):
    resultat = verifier_coherence(extraction(**champs), RECU_LE)
    assert resultat.a_verifier
    assert raison in resultat.raison_verification


def test_models_own_doubt_is_kept():
    e = extraction(a_verifier=True, raison_verification="deux dates possibles", date_limite=None)
    assert verifier_coherence(e, RECU_LE).raison_verification.startswith("deux dates possibles ; ")


@pytest.mark.parametrize("montant", [-5, 1_000_000])
def test_absurd_amounts_are_rejected(montant):
    with pytest.raises(ValidationError):
        extraction(montant=montant)


def test_texts_fit_the_firestore_rules():
    e = extraction(titre="x" * 400, organisme_nom="y" * 400, resume="z" * 900)
    assert (len(e.titre), len(e.organisme_nom), len(e.resume)) == (120, 120, 500)
