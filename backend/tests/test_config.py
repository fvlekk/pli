import pytest

from pli.config import Config
from pli.main import creer_app_depuis_env


def test_auto_uses_claude_only_with_a_key(monkeypatch):
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    monkeypatch.delenv("ANTHROPIC_AUTH_TOKEN", raising=False)
    monkeypatch.delenv("PLI_EXTRACTEUR", raising=False)
    assert Config.depuis_env().extracteur == "regle"
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test")
    assert Config.depuis_env().extracteur == "claude"


def test_refuses_the_auth_emulator_without_the_explicit_flag(monkeypatch):
    monkeypatch.setenv("FIREBASE_AUTH_EMULATOR_HOST", "127.0.0.1:9099")
    monkeypatch.delenv("PLI_AUTH_EMULATEUR", raising=False)
    with pytest.raises(RuntimeError):
        creer_app_depuis_env()


def test_refuses_the_auth_emulator_on_cloud_run(monkeypatch):
    monkeypatch.setenv("FIREBASE_AUTH_EMULATOR_HOST", "127.0.0.1:9099")
    monkeypatch.setenv("PLI_AUTH_EMULATEUR", "1")
    monkeypatch.setenv("K_SERVICE", "pli-api")
    with pytest.raises(RuntimeError):
        creer_app_depuis_env()
