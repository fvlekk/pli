import firebase_admin
import google.auth
import pytest

from pli.auth import JetonInvalide, VerificateurFirebase


@pytest.fixture
def sans_identifiants_google(monkeypatch):
    """Like a host outside Google Cloud (Render): no Application Default Credentials anywhere."""

    def absent(*_args, **_kwargs):
        raise google.auth.exceptions.DefaultCredentialsError("no ADC here")

    monkeypatch.setattr(google.auth, "default", absent)
    monkeypatch.delenv("FIREBASE_AUTH_EMULATOR_HOST", raising=False)
    for app in list(firebase_admin._apps.values()):
        firebase_admin.delete_app(app)
    yield
    for app in list(firebase_admin._apps.values()):
        firebase_admin.delete_app(app)


def test_token_check_needs_no_google_credentials(sans_identifiants_google):
    # A malformed token is refused before any network call: this only checks that firebase-admin does not
    # ask for credentials first (it crashed every request on Render with DefaultCredentialsError).
    with pytest.raises(JetonInvalide):
        VerificateurFirebase("plii-demo").uid("pas-un-jeton")


def test_app_check_needs_no_google_credentials(sans_identifiants_google):
    # Same as the ID token: a malformed App Check token is refused offline, without asking for credentials.
    with pytest.raises(JetonInvalide):
        VerificateurFirebase("plii-demo").app_check("pas-un-jeton")
