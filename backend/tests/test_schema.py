import re
from datetime import date
from pathlib import Path
from typing import get_args

import pytest
from pydantic import ValidationError

from pli.schema import Action, Organisme, verifier_coherence

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


REGLES = (Path(__file__).parents[2] / "firebase" / "firestore.rules").read_text(encoding="utf-8")


@pytest.mark.parametrize(("champ", "valeurs"), [("organisme", Organisme), ("action", Action)])
def test_firestore_rules_accept_every_value_of_the_schema(champ, valeurs):
    liste = re.search(rf"d\.{champ} in \[(.*?)\]", REGLES, re.DOTALL).group(1)
    assert set(re.findall(r"'(\w+)'", liste)) == set(get_args(valeurs))


def test_firestore_rules_and_schema_share_their_text_limits():
    e = extraction(titre="t" * 200, organisme_nom="o" * 200, resume="r" * 900)
    assert f"d.titre.size() <= {len(e.titre)}" in REGLES
    assert f"d.organismeNom.size() <= {len(e.organisme_nom)}" in REGLES
    assert f"d.resume.size() <= {len(e.resume)}" in REGLES


def test_the_app_uses_the_same_text_limits():
    modele = (Path(__file__).parents[2] / "app/lib/modeles/echeance.dart").read_text(encoding="utf-8")
    e = extraction(titre="t" * 200, organisme_nom="o" * 200, resume="r" * 900)
    assert f"const longueurMaxTitre = {len(e.titre)};" in modele
    assert f"const longueurMaxResume = {len(e.resume)};" in modele
