import base64
from datetime import date

from pli.courrier import FormatNonLisible
from pli.extracteurs.claude import ExtractionImpossible, ServiceIndisponible

from .conftest import AUJOURDHUI, AUTH

COURRIER = {"texte": "Montant à payer : 120,00 €. Date limite de paiement : 15/11/2026."}


def test_healthz_is_public(client):
    assert client.get("/healthz").json() == {"ok": True, "extracteur": "faux"}


def test_extraction_needs_a_token(client):
    assert client.post("/v1/extractions", json=COURRIER).status_code == 401


def test_extraction_rejects_an_invalid_token(client):
    reponse = client.post("/v1/extractions", json=COURRIER, headers={"Authorization": "Bearer vole"})
    assert reponse.status_code == 401


def test_extraction_returns_the_extractors_answer(client, extracteur):
    reponse = client.post("/v1/extractions", json=COURRIER, headers=AUTH)
    assert reponse.status_code == 200
    corps = reponse.json()
    assert corps["extraction"]["date_limite"] == "2026-11-15"
    assert corps["source"] == "faux"
    courrier, recu_le = extracteur.appels[0]
    assert courrier.texte == COURRIER["texte"]
    assert recu_le == AUJOURDHUI


def test_responses_carry_security_headers(client):
    reponse = client.post("/v1/extractions", json=COURRIER, headers=AUTH)
    assert reponse.headers["X-Content-Type-Options"] == "nosniff"
    assert reponse.headers["Cache-Control"] == "no-store"


def test_rate_limit_is_per_user(client):
    for _ in range(3):
        assert client.post("/v1/extractions", json=COURRIER, headers=AUTH).status_code == 200
    bloque = client.post("/v1/extractions", json=COURRIER, headers=AUTH)
    assert bloque.status_code == 429
    assert bloque.headers["Retry-After"] == "60"
    autre = {"Authorization": "Bearer ok-bob"}
    assert client.post("/v1/extractions", json=COURRIER, headers=autre).status_code == 200


def test_needs_exactly_one_of_text_or_file(client):
    fichier = {"media_type": "image/png", "donnees_base64": base64.b64encode(b"png").decode()}
    assert client.post("/v1/extractions", json={}, headers=AUTH).status_code == 422
    deux = {**COURRIER, "fichier": fichier}
    assert client.post("/v1/extractions", json=deux, headers=AUTH).status_code == 422


def test_rejects_unknown_file_types(client):
    fichier = {"media_type": "text/html", "donnees_base64": base64.b64encode(b"<script>").decode()}
    assert client.post("/v1/extractions", json={"fichier": fichier}, headers=AUTH).status_code == 422


def test_rejects_bad_base64(client):
    fichier = {"media_type": "application/pdf", "donnees_base64": "pas du base64 !"}
    assert client.post("/v1/extractions", json={"fichier": fichier}, headers=AUTH).status_code == 422


def test_rejects_files_over_the_limit(client):
    gros = {"media_type": "application/pdf", "donnees_base64": base64.b64encode(b"x" * 1001).decode()}
    assert client.post("/v1/extractions", json={"fichier": gros}, headers=AUTH).status_code == 413


def test_rejects_bodies_over_the_limit_before_reading_them(client):
    reponse = client.post("/v1/extractions", json={"texte": "x" * 6000}, headers=AUTH)
    assert reponse.status_code == 413


def test_unreadable_letter_is_a_422(client, extracteur):
    extracteur.erreur = FormatNonLisible("photo")
    assert client.post("/v1/extractions", json=COURRIER, headers=AUTH).status_code == 422


def test_busy_api_is_a_503_with_retry_after(client, extracteur):
    extracteur.erreur = ServiceIndisponible("RateLimitError")
    reponse = client.post("/v1/extractions", json=COURRIER, headers=AUTH)
    assert reponse.status_code == 503
    assert reponse.headers["Retry-After"] == "30"


def test_failed_extraction_is_a_502(client, extracteur):
    extracteur.erreur = ExtractionImpossible("stop_reason=refusal")
    assert client.post("/v1/extractions", json=COURRIER, headers=AUTH).status_code == 502


def test_logs_never_contain_the_letter_or_the_uid(client, capsys):
    courrier_sensible = "Numéro fiscal 1234567890123, Mme Camille MARTIN"
    client.post("/v1/extractions", json={"texte": courrier_sensible}, headers=AUTH)
    journal = capsys.readouterr().out
    assert "extraction" in journal
    assert "1234567890123" not in journal
    assert "MARTIN" not in journal
    assert "alice" not in journal


def test_auth_outage_is_a_503_not_a_500(client):
    reponse = client.post("/v1/extractions", json=COURRIER, headers={"Authorization": "Bearer panne"})
    assert reponse.status_code == 503
    assert reponse.headers["Retry-After"] == "30"


def test_the_phones_date_is_used_within_a_day(client, extracteur):
    client.post("/v1/extractions", json={**COURRIER, "recu_le": "2026-10-11"}, headers=AUTH)
    assert extracteur.appels[-1][1] == date(2026, 10, 11)


def test_an_implausible_phone_date_is_ignored(client, extracteur):
    client.post("/v1/extractions", json={**COURRIER, "recu_le": "2020-01-01"}, headers=AUTH)
    assert extracteur.appels[-1][1] == AUJOURDHUI
