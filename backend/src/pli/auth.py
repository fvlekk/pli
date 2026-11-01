"""Firebase ID token verification. Every route except /healthz needs a valid token."""

from typing import Protocol

import firebase_admin
from firebase_admin import auth as firebase_auth
from firebase_admin import credentials
from google.auth.credentials import AnonymousCredentials


class JetonInvalide(Exception):
    pass


class AuthIndisponible(Exception):
    """The token could not be checked (Google's public keys unreachable): retry later."""


class VerificateurJeton(Protocol):
    def uid(self, jeton: str) -> str: ...


class _SansCompte(credentials.Base):
    """Checking an ID token only needs Google's public keys and the project id, never a service account.

    Without it, firebase-admin looks for Application Default Credentials: they exist on Cloud Run but not on
    another host (Render), where every request failed with DefaultCredentialsError.
    """

    def get_credential(self):
        return AnonymousCredentials()


class VerificateurFirebase:
    """Checks the token's signature, expiry and audience (the Firebase project).

    With FIREBASE_AUTH_EMULATOR_HOST set, firebase-admin accepts the emulator's unsigned tokens instead:
    that variable must never be set in production (main.py refuses to start if it is, without the flag).
    """

    def __init__(self, projet: str | None):
        try:
            firebase_admin.get_app()
        except ValueError:
            # No project id: keep the default credentials, on Google Cloud they also supply the project.
            if projet:
                firebase_admin.initialize_app(credential=_SansCompte(), options={"projectId": projet})
            else:
                firebase_admin.initialize_app()

    def uid(self, jeton: str) -> str:
        try:
            return firebase_auth.verify_id_token(jeton)["uid"]
        except firebase_auth.CertificateFetchError as e:
            raise AuthIndisponible(type(e).__name__) from e
        except (ValueError, firebase_auth.InvalidIdTokenError, firebase_auth.ExpiredIdTokenError) as e:
            raise JetonInvalide(type(e).__name__) from e
