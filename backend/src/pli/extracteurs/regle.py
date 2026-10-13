"""Rule-based extractor: regexes and keywords, no model.

It is the baseline the model must beat on the eval, and the fallback when no API key is configured.
It was written against the `dev` split only.
"""

import re
from datetime import date, timedelta

from pli.courrier import Courrier, texte_du_courrier
from pli.extracteurs.base import Resultat
from pli.schema import Extraction, verifier_coherence

MOIS = {
    "janvier": 1, "février": 2, "fevrier": 2, "mars": 3, "avril": 4, "mai": 5, "juin": 6, "juillet": 7,
    "août": 8, "aout": 8, "septembre": 9, "octobre": 10, "novembre": 11, "décembre": 12, "decembre": 12,
}  # fmt: skip

_DATE_CHIFFRES = r"(\d{1,2})[/.](\d{1,2})[/.](\d{2,4})"
_DATE_LETTRES = r"(1er|\d{1,2})\s+(" + "|".join(MOIS) + r")\s+(\d{4})"
DATE = re.compile(rf"{_DATE_CHIFFRES}|{_DATE_LETTRES}", re.IGNORECASE)

MOTS_ECHEANCE = re.compile(
    r"avant le|au plus tard le|date limite[^:\n]*:|jusqu'au|convoquée? le|est à faire avant le",
    re.IGNORECASE,
)
DELAI_JOURS = re.compile(r"(?:sous|dans un délai de|dans les)\s+(\d{1,3})\s+jours", re.IGNORECASE)
DATE_COURRIER = re.compile(
    r"(?:date d'établissement|date d'envoi(?: de l'avis)?|date de facture|date)\s*:\s*"
    rf"(?:{_DATE_CHIFFRES}|{_DATE_LETTRES})"
    r"|(?:^|,\s*)le\s+"
    rf"(?:{_DATE_CHIFFRES}|{_DATE_LETTRES})",
    re.IGNORECASE | re.MULTILINE,
)

MONTANT = re.compile(r"(\d{1,3}(?: \d{3})*(?:,\d{2})?)\s*(?:€|euros?\b)", re.IGNORECASE)
MOTS_MONTANT = [
    "restant à payer", "à régler", "à payer", "minorée", "solde", "s'élève à", "d'un montant de", "montant",
]  # fmt: skip

ACTIONS = [
    ("aucune", r"aucune démarche"),
    ("se_presenter", r"convoqué"),
    ("declarer", r"\bdéclar(?:er|ez|ation)\b|actualis"),
    ("payer", r"\bpay(?:er|ez)\b|paiement|\brégl(?:er|ez)\b|règlement|rembourser"),
    ("renouveler", r"renouvel"),
    ("envoyer_documents", r"transmettre|envoyer|envoyez|justificatif"),
    ("demander", r"\bdemande\b|\bdemander\b|dossier"),
]

ORGANISMES = [
    ("assurance_maladie", r"assurance maladie|ameli|\bcpam\b"),
    ("impots", r"finances publiques|impots\.gouv|\bimpôts?\b"),
    ("caf", r"\bcaf\b|allocations familiales"),
    ("urssaf", r"urssaf"),
    ("france_travail", r"france travail"),
    ("prefecture", r"préfecture|\banef\b|titre de séjour"),
    ("antai", r"\bantai\b|contravention|amende"),
    ("crous", r"\bcrous\b"),
    ("ants", r"\bants\b|titres sécurisés"),
    ("mutuelle", r"mutuelle"),
    ("assurance", r"assurance"),
    ("energie", r"énergie|électricité|\bgaz\b"),
    ("bailleur", r"bailleur|agence immobilière|gestion locative|loyer"),
]

LIBELLES = {
    "impots": "impôts", "caf": "Caf", "assurance_maladie": "Assurance Maladie", "urssaf": "Urssaf",
    "france_travail": "France Travail", "prefecture": "préfecture", "antai": "amende", "crous": "Crous",
    "ants": "ANTS", "mutuelle": "mutuelle", "assurance": "assurance", "energie": "énergie",
    "bailleur": "logement", "autre": "courrier",
}  # fmt: skip

TITRES = {
    "payer": "Payer",
    "declarer": "Déclarer",
    "envoyer_documents": "Envoyer des documents",
    "renouveler": "Renouveler",
    "se_presenter": "Se présenter",
    "demander": "Faire la demande",
    "repondre": "Répondre",
    "aucune": "Pour information",
}


def _date(groupes: tuple[str | None, ...]) -> date | None:
    j, m, a, jl, ml, al = groupes
    try:
        if j:
            annee = int(a) + 2000 if len(a) == 2 else int(a)
            return date(annee, int(m), int(j))
        if not jl:
            return None
        jour = 1 if jl.lower() == "1er" else int(jl)
        return date(int(al), MOIS[ml.lower()], jour)
    except (ValueError, KeyError, TypeError):
        return None


def _normaliser(texte: str) -> str:
    return texte.replace("\u202f", " ").replace("\xa0", " ").replace("\u2019", "'")


def date_du_courrier(texte: str) -> date | None:
    m = DATE_COURRIER.search(texte)
    if not m:
        return None
    groupes = m.groups()
    return _date(groupes[:6]) or _date(groupes[6:])


def date_limite(texte: str, base: date) -> date | None:
    """First date right after a deadline keyword; otherwise 'within N days' from the letter date."""
    for mot in MOTS_ECHEANCE.finditer(texte):
        fenetre = texte[mot.end() : mot.end() + 45]
        m = DATE.search(fenetre)
        if m:
            return _date(m.groups())
    delai = DELAI_JOURS.search(texte)
    if delai:
        return base + timedelta(days=int(delai.group(1)))
    return None


def montant(texte: str) -> float | None:
    """The amount on the line with the strongest payment keyword."""
    meilleur: tuple[int, float] | None = None
    for ligne in texte.splitlines():
        m = MONTANT.search(ligne)
        if not m:
            continue
        bas = ligne.lower()
        rangs = [i for i, mot in enumerate(MOTS_MONTANT) if mot in bas]
        if not rangs:
            continue
        valeur = float(m.group(1).replace(" ", "").replace(",", "."))
        if meilleur is None or rangs[0] < meilleur[0]:
            meilleur = (rangs[0], valeur)
    return meilleur[1] if meilleur else None


def _premier(regles: list[tuple[str, str]], texte: str) -> str | None:
    for valeur, motif in regles:
        if re.search(motif, texte, re.IGNORECASE):
            return valeur
    return None


def organisme(texte: str) -> str:
    """The letterhead decides, line by line, before the body (which may mention other organisations)."""
    entete = [ligne for ligne in texte.splitlines() if ligne.strip()][:3]
    for ligne in entete:
        trouve = _premier(ORGANISMES, ligne)
        if trouve:
            return trouve
    return _premier(ORGANISMES, texte) or "autre"


NOMS_MOIS = [None, *(m for m in MOIS if m not in ("fevrier", "aout", "decembre"))]


def _resume(action: str, echeance: date | None, somme: float | None) -> str:
    if action == "aucune":
        return "Ce courrier t'informe : il n'y a rien à faire."
    phrase = TITRES[action]
    if somme is not None:
        phrase += f" {somme:.2f} €".replace(".", ",").replace(",00 €", " €")
    if echeance:
        phrase += f" avant le {echeance.day} {NOMS_MOIS[echeance.month]} {echeance.year}"
    return phrase + "."


class ExtracteurRegle:
    nom = "regle"

    def extraire(self, courrier: Courrier, recu_le: date) -> Resultat:
        texte = _normaliser(texte_du_courrier(courrier))
        action = _premier(ACTIONS, texte) or "aucune"
        ecrit_le = date_du_courrier(texte)
        echeance = None if action == "aucune" else date_limite(texte, ecrit_le or recu_le)
        somme = montant(texte)
        if action != "payer" and "timbre" not in texte.lower():
            somme = None
        nom = next((ligne.strip() for ligne in texte.splitlines() if ligne.strip()), "Courrier")
        categorie = organisme(texte)
        extraction = Extraction(
            organisme=categorie,
            organisme_nom=nom[:1].upper() + nom[1:].lower(),
            action=action,
            titre=f"{TITRES[action]} ({LIBELLES[categorie]})",
            date_limite=echeance,
            montant=somme,
            date_courrier=ecrit_le,
            resume=_resume(action, echeance, somme),
            a_verifier=False,
            raison_verification=None,
        )
        return Resultat(extraction=verifier_coherence(extraction, recu_le), source=self.nom)
