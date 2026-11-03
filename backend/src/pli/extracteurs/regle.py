"""Rule-based extractor: regexes and keywords, no model.

It is the baseline the model must beat on the eval, and the fallback when no API key is configured.
Its rules were written against the `dev`, `test` and `inedit` splits: only `inedit2`, written after them, is
held out for it.
"""

import re
from datetime import date, timedelta
from typing import NamedTuple

from pli.courrier import Courrier, texte_du_courrier
from pli.extracteurs.base import Resultat
from pli.schema import Extraction, verifier_coherence

MOIS = {
    "janvier": 1, "février": 2, "fevrier": 2, "mars": 3, "avril": 4, "mai": 5, "juin": 6, "juillet": 7,
    "août": 8, "aout": 8, "septembre": 9, "octobre": 10, "novembre": 11, "décembre": 12, "decembre": 12,
}  # fmt: skip
NOMBRES = {
    "un": 1, "une": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "six": 6, "sept": 7, "huit": 8,
    "dix": 10, "quinze": 15, "vingt": 20, "trente": 30,
}  # fmt: skip

_MOIS = "|".join(MOIS)
_DATE_CHIFFRES = r"(\d{1,2})[/.](\d{1,2})[/.](\d{2,4})"
_DATE_LETTRES = rf"(1er|\d{{1,2}})\s+({_MOIS})\s+(\d{{4}})"
DATE = re.compile(rf"{_DATE_CHIFFRES}|{_DATE_LETTRES}", re.IGNORECASE)
DATE_SANS_ANNEE = re.compile(rf"(1er|\d{{1,2}})\s+({_MOIS})\b(?!\s+\d{{4}})", re.IGNORECASE)
_NOMBRE = r"(\d{1,3}|" + "|".join(NOMBRES) + r")"

MOTS_ECHEANCE = re.compile(
    r"avant le|au plus tard le|date limite[^:\n]*:|jusqu'au|convoquée?\b[^.;\n]{0,60}?\ble\b|"
    r"rendez-vous (?:est fixé )?le|est à faire avant le",
    re.IGNORECASE,
)
PERIODE = re.compile(rf"\bdu\s+(?:1er|\d{{1,2}})(?:\s+(?:{_MOIS}))?(?:\s+\d{{4}})?\s+au\s+", re.IGNORECASE)
DELAI = re.compile(
    rf"(?:sous|dans un délai de|dans les|disposez de|dispose de|disposes de)\s+{_NOMBRE}\s+(jours|mois)",
    re.IGNORECASE,
)
MOIS_AVANT = re.compile(rf"{_NOMBRE}\s+mois\s+avant\b", re.IGNORECASE)
REFERENCE = re.compile(
    r"(?:prendra fin|prend fin|expire|expiration|arrive à échéance)[^.\n]{0,30}?\b(?:le|au)\s+"
)
ZONE = re.compile(r"départements?\s+(\d{2,3})\s+à\s+(\d{2,3})\s*:\s*([^;\n]*)", re.IGNORECASE)
CODE_POSTAL = re.compile(r"\b(\d{5})\s+[A-ZÉÈÀ][A-ZÉÈÀ' -]+$", re.MULTILINE)
DATE_COURRIER = re.compile(
    r"(?:date d'établissement|date d'envoi(?: de l'avis)?|date de facture|date)\s*:\s*"
    rf"(?:{_DATE_CHIFFRES}|{_DATE_LETTRES})"
    r"|(?:^|,\s*)le\s+"
    rf"(?:{_DATE_CHIFFRES}|{_DATE_LETTRES})",
    re.IGNORECASE | re.MULTILINE,
)

MONTANT = re.compile(r"(\d{1,3}(?: \d{3})*(?:,\d{2})?)\s*(?:€|euros?\b)", re.IGNORECASE)
MOTS_MONTANT = [
    "restant à payer", "reste à payer", "soit un total", "réduit", "minorée", "à régler", "à payer", "solde",
    "s'élève à", "d'un montant de", "montant", "dépôt de garantie", "cotisation", "ttc",
]  # fmt: skip
# Amounts that are never the one to pay: penalties, what was already paid, what the recipient receives.
MOTS_AUTRE_MONTANT = re.compile(
    r"majoration|pénalité|déjà (?:payé|réglé|effectué)|prélèvements déjà|vous est (?:remboursé|versé)|"
    r"\bversée? sur votre compte|provisions versées|\bht\b|tva",
    re.IGNORECASE,
)

AUCUNE = re.compile(r"aucune démarche|rien à faire|sera prélevée? automatiquement")
# Verbs of the gesture, in priority order for the whole letter; in the deadline's sentence the first one wins.
VERBES = [
    ("se_presenter", r"convoqu|en personne|vous présenter|venir le retirer"),
    ("declarer", r"\bdéclar(?:er|ez)\b|\bactualis"),
    ("payer", r"\bpay(?:er|ez)\b|paiement|\brégl(?:er|ez)\b|règlement|rembourser|régularis|impayé"),
    ("renouveler", r"renouvel"),
    ("envoyer_documents", r"transmet(?:tre|tez)|\benvoy(?:er|ez)\b|renvoy|retourn(?:er|ez)|justificatif"),
    ("demander", r"\bdemander\b|\bdemandez\b|constituer"),
]
# Nouns that only hint at the gesture: used when no verb is found.
NOMS = [("declarer", r"déclaration"), ("demander", r"\bdemande\b|dossier")]
INJECTION = re.compile(
    r"ignorer? (?:toutes )?(?:tes|vos|les) (?:instructions|consignes)|assistant|traitement automatisé|"
    r"lecture automatique|intelligence artificielle",
    re.IGNORECASE,
)

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
    ("bailleur", r"bailleur|agence immobilière|gestion locative|loyer|\bsci\b|charges locatives"),
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


class Echeance(NamedTuple):
    date: date | None
    phrase: str
    raisons: tuple[str, ...] = ()


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


def _nombre(mot: str) -> int:
    return int(mot) if mot.isdigit() else NOMBRES[mot.lower()]


def _plus_mois(d: date, mois: int) -> date:
    """Same day `mois` months later (or earlier if negative), clamped to the month's last day."""
    total = d.year * 12 + d.month - 1 + mois
    annee, numero = divmod(total, 12)
    for jour in range(d.day, 0, -1):
        try:
            return date(annee, numero + 1, jour)
        except ValueError:
            continue
    raise ValueError(d)


def _normaliser(texte: str) -> str:
    return texte.replace("\u202f", " ").replace("\xa0", " ").replace("\u2019", "'")


def _phrase(texte: str, debut: int, fin: int) -> str:
    """The sentence (or block between blank lines) around texte[debut:fin]."""
    bornes = [m.end() for m in re.finditer(r"[.!?;](?=\s)|\n\s*\n", texte)]
    gauche = max((b for b in bornes if b <= debut), default=0)
    droite = min((b for b in bornes if b > fin), default=len(texte))
    return texte[gauche:droite]


def date_du_courrier(texte: str) -> date | None:
    m = DATE_COURRIER.search(texte)
    if not m:
        return None
    groupes = m.groups()
    return _date(groupes[:6]) or _date(groupes[6:])


def _date_apres(texte: str, position: int, base: date) -> tuple[date | None, int, tuple[str, ...]]:
    """The date written right after `position`; a date with no year takes the year that makes it come next."""
    fenetre = texte[position : position + 45]
    m = DATE.search(fenetre)
    if m:
        return _date(m.groups()), position + m.end(), ()
    m = DATE_SANS_ANNEE.search(fenetre)
    if not m:
        return None, position, ()
    jour = 1 if m.group(1).lower() == "1er" else int(m.group(1))
    try:
        d = date(base.year, MOIS[m.group(2).lower()], jour)
    except ValueError:
        return None, position, ()
    if d < base:
        d = d.replace(year=d.year + 1)
    return d, position + m.end(), ("année de la date limite déduite du courrier",)


def _par_zone(texte: str) -> Echeance | None:
    """Deadlines by département (tax returns): the one for the address's postcode, else the earliest."""
    zones = []
    for m in ZONE.finditer(texte):
        d = DATE.search(m.group(3))
        if d and _date(d.groups()):
            zones.append((int(m.group(1)), int(m.group(2)), _date(d.groups()), m))
    if len(zones) < 2:
        return None
    phrase = _phrase(texte, zones[0][3].start(), zones[-1][3].end())
    cp = CODE_POSTAL.search(texte)
    if cp:
        departement = int(cp.group(1)[:3] if cp.group(1).startswith("97") else cp.group(1)[:2])
        for debut, fin, d, _ in zones:
            if debut <= departement <= fin:
                return Echeance(d, phrase)
    return Echeance(
        min(z[2] for z in zones), phrase, ("date limite selon le département : vérifie la tienne",)
    )


def echeance(texte: str, base: date, recu_le: date | None = None) -> Echeance:
    """The deadline, and the sentence it was read in (where the action and the amount usually are).

    Order: explicit keywords, deadlines by département, periods (their end), « N mois avant » a date written
    earlier, then « sous N jours/mois » from the letter's date (or from reception when the letter says so).
    « avant le 25 » is read as the 24th: the safe reading, since a reminder a day early costs nothing.
    """
    recu_le = recu_le or base
    for mot in MOTS_ECHEANCE.finditer(texte):
        d, fin, raisons = _date_apres(texte, mot.end(), base)
        if d:
            if mot.group(0).lower().endswith("avant le"):
                d -= timedelta(days=1)
            return Echeance(d, _phrase(texte, mot.start(), fin), raisons)
    zone = _par_zone(texte)
    if zone:
        return zone
    for m in PERIODE.finditer(texte):
        d, fin, raisons = _date_apres(texte, m.end(), base)
        if d:
            return Echeance(d, _phrase(texte, m.start(), fin), raisons)
    avant = MOIS_AVANT.search(texte)
    reference = REFERENCE.search(texte)
    if avant and reference:
        d, _, raisons = _date_apres(texte, reference.end(), base)
        if d:
            return Echeance(
                _plus_mois(d, -_nombre(avant.group(1))), _phrase(texte, avant.start(), avant.end())
            )
    delai = DELAI.search(texte)
    if delai:
        n, unite = _nombre(delai.group(1)), delai.group(2).lower()
        phrase = _phrase(texte, delai.start(), delai.end())
        depart = recu_le if "réception" in phrase.lower() else base
        d = _plus_mois(depart, n) if unite == "mois" else depart + timedelta(days=n)
        return Echeance(d, phrase)
    return Echeance(None, "")


def date_limite(texte: str, base: date, recu_le: date | None = None) -> date | None:
    return echeance(texte, base, recu_le).date


def _meilleur_montant(lignes: list[str], sans_mot_cle: bool) -> float | None:
    meilleur: tuple[int, float] | None = None
    for ligne in lignes:
        if MOTS_AUTRE_MONTANT.search(ligne):
            continue
        bas = ligne.lower()
        for m in MONTANT.finditer(ligne):
            rangs = [i for i, mot in enumerate(MOTS_MONTANT) if mot in bas[: m.end() + 40]]
            if not rangs and not sans_mot_cle:
                continue
            rang = rangs[0] if rangs else len(MOTS_MONTANT)
            valeur = float(m.group(1).replace(" ", "").replace(",", "."))
            if meilleur is None or rang < meilleur[0]:
                meilleur = (rang, valeur)
    return meilleur[1] if meilleur else None


def montant(texte: str, phrase: str = "") -> float | None:
    """The amount in the deadline's sentence if there is one, else the one with the strongest payment keyword.

    Penalties, amounts already paid and amounts paid to the recipient are skipped.
    """
    if phrase:
        dans_phrase = _meilleur_montant(re.split(r"(?<=[.;])\s+|\n", phrase), sans_mot_cle=True)
        if dans_phrase is not None:
            return dans_phrase
    return _meilleur_montant(texte.splitlines(), sans_mot_cle=False)


def _premier(regles: list[tuple[str, str]], texte: str) -> str | None:
    for valeur, motif in regles:
        if re.search(motif, texte, re.IGNORECASE):
            return valeur
    return None


def _sans_demarche(texte: str) -> bool:
    """« Vous n'avez rien à faire », not inside an « if » (« si vous avez déjà payé, … rien à faire »)."""
    for m in AUCUNE.finditer(texte.lower()):
        if not re.search(r"\bsi\b", _phrase(texte.lower(), m.start(), m.end())):
            return True
    return False


def _premier_dans(regles: list[tuple[str, str]], texte: str) -> str | None:
    """The rule whose match comes first in the text (the gesture the sentence asks first)."""
    trouves = [
        (m.start(), valeur) for valeur, motif in regles if (m := re.search(motif, texte, re.IGNORECASE))
    ]
    return min(trouves)[1] if trouves else None


def action(texte: str, phrase: str = "") -> str:
    """The gesture asked in the deadline's sentence, else in the whole letter; verbs before nouns."""
    if _sans_demarche(texte):
        return "aucune"
    return (
        (phrase and (_premier_dans(VERBES, phrase) or _premier_dans(NOMS, phrase)))
        or _premier(VERBES, texte)
        or _premier(NOMS, texte)
        or "aucune"
    )


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
        ecrit_le = date_du_courrier(texte)
        trouvee = echeance(texte, ecrit_le or recu_le, recu_le)
        geste = action(texte, trouvee.phrase)
        date_fin = None if geste == "aucune" else trouvee.date
        somme = montant(texte, trouvee.phrase)
        if geste != "payer" and "timbre" not in texte.lower():
            somme = None
        nom = next((ligne.strip() for ligne in texte.splitlines() if ligne.strip()), "Courrier")
        categorie = organisme(texte)
        raisons = list(trouvee.raisons) if date_fin else []
        if INJECTION.search(texte):
            raisons.append("le courrier contient des consignes adressées à un système de lecture automatique")
        extraction = Extraction(
            organisme=categorie,
            organisme_nom=nom[:1].upper() + nom[1:].lower(),
            action=geste,
            titre=f"{TITRES[geste]} ({LIBELLES[categorie]})",
            date_limite=date_fin,
            montant=somme,
            date_courrier=ecrit_le,
            resume=_resume(geste, date_fin, somme),
            a_verifier=bool(raisons),
            raison_verification=" ; ".join(raisons) or None,
        )
        return Resultat(extraction=verifier_coherence(extraction, recu_le), source=self.nom)
