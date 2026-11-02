import base64
import io
import json
from datetime import date

from fastapi.testclient import TestClient
from pypdf import PdfWriter

from pli.courrier import FormatNonLisible
from pli.extracteurs.claude import ExtractionImpossible, ServiceIndisponible
from pli.main import creer_app

from .conftest import AUJOURDHUI, AUTH, FauxVerificateur, config

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


def client_avec(extracteur, **reglages) -> TestClient:
    app = creer_app(config(**reglages), extracteur, FauxVerificateur(), aujourdhui=lambda: AUJOURDHUI)
    return TestClient(app)


def journal_extraction(capsys) -> dict:
    lignes = [json.loads(ligne) for ligne in capsys.readouterr().out.splitlines() if ligne.startswith("{")]
    return next(ligne for ligne in lignes if ligne["message"] == "extraction")


def test_app_check_is_only_logged_while_not_required(client, capsys):
    assert client.post("/v1/extractions", json=COURRIER, headers=AUTH).status_code == 200
    assert journal_extraction(capsys)["app_check"] == "absent"
    faux = {**AUTH, "X-Firebase-AppCheck": "forge"}
    assert client.post("/v1/extractions", json=COURRIER, headers=faux).status_code == 200
    assert journal_extraction(capsys)["app_check"] == "invalide"
    bon = {**AUTH, "X-Firebase-AppCheck": "app-ok"}
    assert client.post("/v1/extractions", json=COURRIER, headers=bon).status_code == 200
    assert journal_extraction(capsys)["app_check"] == "ok"


def test_required_app_check_refuses_scripts_before_reading_or_counting(extracteur):
    client = client_avec(extracteur, app_check_obligatoire=True)
    for entetes in (AUTH, {**AUTH, "X-Firebase-AppCheck": "forge"}):
        assert client.post("/v1/extractions", json=COURRIER, headers=entetes).status_code == 401
    assert extracteur.appels == []
    # Refused calls did not use the user's quota (3 a minute in the tests).
    bon = {**AUTH, "X-Firebase-AppCheck": "app-ok"}
    for _ in range(3):
        assert client.post("/v1/extractions", json=COURRIER, headers=bon).status_code == 200


def test_required_app_check_outage_is_a_503(extracteur):
    client = client_avec(extracteur, app_check_obligatoire=True)
    reponse = client.post(
        "/v1/extractions", json=COURRIER, headers={**AUTH, "X-Firebase-AppCheck": "app-panne"}
    )
    assert reponse.status_code == 503
    assert reponse.headers["Retry-After"] == "30"


def test_cors_lets_the_app_send_its_app_check_token(client):
    reponse = client.options(
        "/v1/extractions",
        headers={
            "Origin": "http://localhost:5173",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "authorization,content-type,x-firebase-appcheck",
        },
    )
    assert reponse.status_code == 200
    assert "x-firebase-appcheck" in reponse.headers["access-control-allow-headers"].lower()


def pdf(pages: int) -> dict:
    ecrivain = PdfWriter()
    for _ in range(pages):
        ecrivain.add_blank_page(width=595, height=842)
    tampon = io.BytesIO()
    ecrivain.write(tampon)
    return {"media_type": "application/pdf", "donnees_base64": base64.b64encode(tampon.getvalue()).decode()}


def test_a_pdf_over_the_page_limit_never_reaches_the_extractor(extracteur):
    client = client_avec(extracteur, taille_max_octets=100_000)
    reponse = client.post("/v1/extractions", json={"fichier": pdf(3)}, headers=AUTH)
    assert reponse.status_code == 422
    assert "2 pages maximum" in reponse.json()["detail"]
    assert extracteur.appels == []
    assert client.post("/v1/extractions", json={"fichier": pdf(2)}, headers=AUTH).status_code == 200


def test_a_broken_pdf_is_a_422_not_a_500(extracteur):
    client = client_avec(extracteur, taille_max_octets=100_000)
    casse = {"media_type": "application/pdf", "donnees_base64": base64.b64encode(b"%PDF-1.7 rien").decode()}
    assert client.post("/v1/extractions", json={"fichier": casse}, headers=AUTH).status_code == 422
    assert extracteur.appels == []
