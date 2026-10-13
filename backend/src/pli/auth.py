"""Firebase ID token verification. Every route except /healthz needs a valid token."""

from typing import Protocol

import firebase_admin
from firebase_admin import auth as firebase_auth


class JetonInvalide(Exception):
    pass


class AuthIndisponible(Exception):
    """The token could not be checked (Google's public keys unreachable): retry later."""


class VerificateurJeton(Protocol):
    def uid(self, jeton: str) -> str: ...


class VerificateurFirebase:
    """Checks the token's signature, expiry and audience (the Firebase project).

    With FIREBASE_AUTH_EMULATOR_HOST set, firebase-admin accepts the emulator's unsigned tokens instead:
    that variable must never be set in production (main.py refuses to start if it is, without the flag).
    """

    def __init__(self, projet: str | None):
        try:
            firebase_admin.get_app()
        except ValueError:
            firebase_admin.initialize_app(options={"projectId": projet} if projet else None)

    def uid(self, jeton: str) -> str:
        try:
            return firebase_auth.verify_id_token(jeton)["uid"]
        except firebase_auth.CertificateFetchError as e:
            raise AuthIndisponible(type(e).__name__) from e
        except (ValueError, firebase_auth.InvalidIdTokenError, firebase_auth.ExpiredIdTokenError) as e:
            raise JetonInvalide(type(e).__name__) from e
