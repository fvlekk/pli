"""Structured logs for Cloud Logging. Never the letter, never the raw uid."""

import hashlib
import json
import sys


def uid_masque(uid: str) -> str:
    return hashlib.sha256(uid.encode()).hexdigest()[:12]


def journaliser(message: str, severite: str = "INFO", **champs) -> None:
    ligne = json.dumps({"severity": severite, "message": message, **champs}, ensure_ascii=False)
    print(ligne, file=sys.stdout, flush=True)
