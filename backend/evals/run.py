"""Scores an extractor on the synthetic letters.

    uv run python -m evals.run --extracteur regle --split dev
    uv run python -m evals.run --extracteur claude --split test   # paid: needs ANTHROPIC_API_KEY

The headline is `erreurs_silencieuses`: a deadline that is missing or later than the real one, without the
app asking the user to check. That is the error that makes someone miss a payment.
"""

import argparse
import json
import sys
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path

from pli.courrier import Courrier
from pli.extracteurs.base import Extracteur

DOSSIER = Path(__file__).parent
CHAMPS = ("organisme", "action", "date_limite", "montant")

# USD per million tokens (input, output), to estimate what a run costs.
PRIX = {"claude-opus-5-5": (4.0, 20.0), "claude-sonnet-5-5": (2.0, 10.0), "claude-haiku-5-5": (0.10, 0.50)}


@dataclass
class Bilan:
    total: int = 0
    justes: dict[str, int] = field(default_factory=lambda: dict.fromkeys(CHAMPS, 0))
    tout_juste: int = 0
    date_trop_tardive: int = 0
    date_manquante: int = 0
    erreurs_silencieuses: int = 0
    signales: int = 0
    echecs: int = 0
    jetons_entree: int = 0
    jetons_sortie: int = 0
    lignes: list[dict] = field(default_factory=list)


def charger(split: str) -> list[dict]:
    lignes = [
        json.loads(ligne) for ligne in (DOSSIER / "attendu.jsonl").read_text("utf-8").splitlines() if ligne
    ]
    return [ligne for ligne in lignes if split == "tout" or ligne["split"] == split]


def comparer(attendu: dict, obtenu: dict) -> dict[str, bool]:
    ok = {
        "organisme": obtenu["organisme"] == attendu["organisme"],
        "action": obtenu["action"] == attendu["action"],
        "date_limite": obtenu["date_limite"] == attendu["date_limite"],
    }
    a, o = attendu["montant"], obtenu["montant"]
    ok["montant"] = (a is None and o is None) or (a is not None and o is not None and abs(a - o) < 0.01)
    return ok


def evaluer(extracteur: Extracteur, cas: list[dict]) -> Bilan:
    bilan = Bilan()
    for attendu in cas:
        bilan.total += 1
        texte = (DOSSIER / "dataset" / f"{attendu['id']}.txt").read_text("utf-8")
        try:
            resultat = extracteur.extraire(Courrier(texte=texte), date.fromisoformat(attendu["recu_le"]))
        except Exception as e:  # noqa: BLE001 - one failing letter must not stop the run
            bilan.echecs += 1
            bilan.lignes.append({"id": attendu["id"], "erreur": f"{type(e).__name__}: {e}"})
            continue
        obtenu = resultat.extraction.model_dump(mode="json")
        ok = comparer(attendu, obtenu)
        for champ, juste in ok.items():
            bilan.justes[champ] += juste
        bilan.tout_juste += all(ok.values())
        bilan.signales += obtenu["a_verifier"]
        bilan.jetons_entree += resultat.jetons_entree or 0
        bilan.jetons_sortie += resultat.jetons_sortie or 0

        risque = None
        if attendu["date_limite"]:
            if obtenu["date_limite"] is None:
                risque = "date_manquante"
            elif obtenu["date_limite"] > attendu["date_limite"]:
                risque = "date_trop_tardive"
        if risque:
            setattr(bilan, risque, getattr(bilan, risque) + 1)
            bilan.erreurs_silencieuses += not obtenu["a_verifier"]
        bilan.lignes.append(
            {
                "id": attendu["id"],
                "faux": [champ for champ, juste in ok.items() if not juste],
                "risque": risque,
                "a_verifier": obtenu["a_verifier"],
                "obtenu": {champ: obtenu[champ] for champ in CHAMPS},
                "attendu": {champ: attendu[champ] for champ in CHAMPS},
            }
        )
    return bilan


def afficher(bilan: Bilan, nom: str, split: str, modele: str | None) -> str:
    n = bilan.total or 1
    lignes = [
        f"Extracteur {nom}{f' ({modele})' if modele else ''} · split {split} · {bilan.total} courriers",
        "",
    ]
    for champ in CHAMPS:
        lignes.append(
            f"  {champ:<14} {bilan.justes[champ]:>3}/{bilan.total}  {100 * bilan.justes[champ] / n:5.1f} %"
        )
    lignes += [
        f"  {'tout juste':<14} {bilan.tout_juste:>3}/{bilan.total}  {100 * bilan.tout_juste / n:5.1f} %",
        "",
        f"  date trop tardive     {bilan.date_trop_tardive}",
        f"  date manquante        {bilan.date_manquante}",
        f"  erreurs silencieuses  {bilan.erreurs_silencieuses}   (date fausse et non signalée)",
        f"  signalés à vérifier   {bilan.signales}",
        f"  échecs                {bilan.echecs}",
    ]
    if bilan.jetons_entree and modele in PRIX:
        entree, sortie = PRIX[modele]
        cout = (bilan.jetons_entree * entree + bilan.jetons_sortie * sortie) / 1_000_000
        lignes.append(f"  jetons {bilan.jetons_entree} entrée / {bilan.jetons_sortie} sortie · ~{cout:.3f} $")
    erreurs = [ligne for ligne in bilan.lignes if ligne.get("faux") or ligne.get("erreur")]
    if erreurs:
        lignes += ["", "Erreurs :"]
        for ligne in erreurs:
            if "erreur" in ligne:
                lignes.append(f"  {ligne['id']}: {ligne['erreur']}")
                continue
            detail = ", ".join(f"{c} {ligne['obtenu'][c]!r} ≠ {ligne['attendu'][c]!r}" for c in ligne["faux"])
            drapeau = " [signalé]" if ligne["a_verifier"] else ""
            lignes.append(f"  {ligne['id']}: {detail}{drapeau}")
    return "\n".join(lignes)


def construire(nom: str) -> Extracteur:
    if nom == "regle":
        from pli.extracteurs.regle import ExtracteurRegle

        return ExtracteurRegle()
    from pli.config import Config
    from pli.extracteurs.claude import ExtracteurClaude

    return ExtracteurClaude.depuis_config(Config.depuis_env())


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--extracteur", choices=["regle", "claude"], default="regle")
    parser.add_argument("--split", choices=["dev", "test", "tout"], default="dev")
    parser.add_argument(
        "--max-silencieuses", type=int, default=None, help="exit 1 above this many silent errors"
    )
    args = parser.parse_args()

    extracteur = construire(args.extracteur)
    bilan = evaluer(extracteur, charger(args.split))
    modele = getattr(extracteur, "modele", None)
    print(afficher(bilan, args.extracteur, args.split, modele))

    sortie = DOSSIER / "resultats" / f"{args.extracteur}-{args.split}.json"
    sortie.parent.mkdir(exist_ok=True)
    resume = {k: v for k, v in bilan.__dict__.items() if k != "lignes"}
    sortie.write_text(
        json.dumps({"modele": modele, **resume, "lignes": bilan.lignes}, indent=2, ensure_ascii=False)
    )

    if args.max_silencieuses is not None and bilan.erreurs_silencieuses > args.max_silencieuses:
        print(
            f"\nÉCHEC : {bilan.erreurs_silencieuses} erreurs silencieuses (maximum {args.max_silencieuses})"
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
