import asyncio
import base64
import gc
import io
import json
import threading
import weakref
from concurrent.futures import ThreadPoolExecutor
from datetime import date

import httpx
import pytest
from fastapi.testclient import TestClient
from pypdf import PdfWriter

from pli.courrier import FormatNonLisible
from pli.extracteurs.claude import ExtractionImpossible, ServiceIndisponible
from pli.main import creer_app

from .conftest import AUJOURDHUI, AUTH, FauxExtracteur, FauxVerificateur, config

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


def test_daily_limit_answers_429_and_says_tomorrow(extracteur):
    client = client_avec(extracteur, requetes_par_jour=1)
    assert client.post("/v1/extractions", json=COURRIER, headers=AUTH).status_code == 200
    reponse = client.post("/v1/extractions", json=COURRIER, headers=AUTH)
    assert reponse.status_code == 429
    assert "demain" in reponse.json()["detail"]
    assert len(extracteur.appels) == 1


def test_no_token_is_refused_before_the_body_is_read(client):
    reponse = client.post(
        "/v1/extractions", content=b"{pas du json", headers={"Content-Type": "application/json"}
    )
    assert reponse.status_code == 401


def test_rate_limit_is_checked_before_the_body_is_read(extracteur):
    client = client_avec(extracteur, requetes_par_minute=1)
    assert client.post("/v1/extractions", json=COURRIER, headers=AUTH).status_code == 200
    assert client.post("/v1/extractions", content=b"{pas du json", headers=AUTH).status_code == 429


@pytest.mark.parametrize(
    "corps",
    [b"{pas du json", b'{"texte":"\\ud800 a"}', b"null", b"[" * 900, b'{"texte":"\xff"}'],
    ids=["cassé", "surrogate", "null", "profond", "non-utf8"],
)
def test_a_malformed_body_is_a_short_422_that_echoes_nothing(client, extracteur, corps):
    reponse = client.post("/v1/extractions", content=corps, headers=AUTH)
    assert reponse.status_code == 422
    assert isinstance(reponse.json()["detail"], str)
    assert extracteur.appels == []


def test_a_refused_letter_is_not_echoed(extracteur):
    client = client_avec(extracteur, taille_max_octets=100_000)
    reponse = client.post("/v1/extractions", json={"texte": "MARTIN" + "a" * 50_001}, headers=AUTH)
    assert reponse.status_code == 422
    assert "MARTIN" not in reponse.text


def test_too_many_readings_at_once_are_refused_then_the_place_is_freed():
    entree, sortie = threading.Event(), threading.Event()

    class Lent(FauxExtracteur):
        def extraire(self, courrier, recu_le):
            entree.set()
            sortie.wait(5)
            return super().extraire(courrier, recu_le)

    client = client_avec(Lent(), lectures_simultanees=1, requetes_par_minute=10)
    with ThreadPoolExecutor(1) as fond:
        premiere = fond.submit(client.post, "/v1/extractions", json=COURRIER, headers=AUTH)
        assert entree.wait(5)
        occupe = client.post("/v1/extractions", json=COURRIER, headers=AUTH)
        sortie.set()
        assert premiere.result().status_code == 200
    assert occupe.status_code == 503
    assert client.post("/v1/extractions", json=COURRIER, headers=AUTH).status_code == 200


def test_a_failed_reading_frees_its_place(extracteur):
    client = client_avec(extracteur, lectures_simultanees=1, requetes_par_minute=10)
    extracteur.erreur = ServiceIndisponible("x")
    assert client.post("/v1/extractions", json=COURRIER, headers=AUTH).status_code == 503
    assert client.post("/v1/extractions", json={"texte": " "}, headers=AUTH).status_code == 422
    extracteur.erreur = None
    assert client.post("/v1/extractions", json=COURRIER, headers=AUTH).status_code == 200


def test_a_body_that_never_arrives_frees_its_place(extracteur, monkeypatch):
    monkeypatch.setattr("pli.main.ATTENTE_CORPS", 0.05)
    app = creer_app(
        config(lectures_simultanees=1), extracteur, FauxVerificateur(), aujourdhui=lambda: AUJOURDHUI
    )

    async def scenario() -> tuple[int, int]:
        async def corps_bloque():
            yield b"{"
            await asyncio.sleep(30)

        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://t") as client:
            entetes = {**AUTH, "Content-Length": "100"}
            bloque = await client.post("/v1/extractions", content=corps_bloque(), headers=entetes)
            suivant = await client.post("/v1/extractions", json=COURRIER, headers=AUTH)
            return bloque.status_code, suivant.status_code

    assert asyncio.run(scenario()) == (408, 200)


def test_a_client_that_leaves_while_sending_is_refused_cleanly(extracteur):
    app = creer_app(
        config(lectures_simultanees=1), extracteur, FauxVerificateur(), aujourdhui=lambda: AUJOURDHUI
    )
    envoyes = []

    async def recevoir():
        return {"type": "http.disconnect"}

    async def envoyer(message):
        envoyes.append(message)

    portee = {
        "type": "http",
        "asgi": {"version": "3.0"},
        "http_version": "1.1",
        "method": "POST",
        "path": "/v1/extractions",
        "raw_path": b"/v1/extractions",
        "query_string": b"",
        "root_path": "",
        "scheme": "http",
        "client": ("127.0.0.1", 1),
        "server": ("t", 80),
        "headers": [
            (b"content-length", b"100"),
            *((k.lower().encode(), v.encode()) for k, v in AUTH.items()),
        ],
    }
    asyncio.run(app(portee, recevoir, envoyer))
    assert envoyes[0]["status"] == 400
    assert extracteur.appels == []
    assert TestClient(app).post("/v1/extractions", json=COURRIER, headers=AUTH).status_code == 200, (
        "place freed"
    )


def test_a_finished_reading_gives_its_memory_back_at_once(extracteur):
    """A failed call leaves the letter in reference cycles: waiting for a full collection took 650 MB."""

    class Lettre:
        pass

    lettre = Lettre()
    lettre.moi = lettre
    trace = weakref.ref(lettre)
    del lettre
    client = TestClient(creer_app(config(), extracteur, FauxVerificateur(), aujourdhui=lambda: AUJOURDHUI))
    gc.disable()
    try:
        assert client.post("/v1/extractions", json=COURRIER, headers=AUTH).status_code == 200
        assert trace() is None
    finally:
        gc.enable()


def test_refused_requests_cost_no_daily_quota(extracteur):
    client = client_avec(extracteur, requetes_par_jour=1)
    assert client.post("/v1/extractions", json=image(b"pas une image"), headers=AUTH).status_code == 422
    assert client.post("/v1/extractions", json={"texte": "   "}, headers=AUTH).status_code == 422
    assert client.post("/v1/extractions", json=COURRIER, headers=AUTH).status_code == 200


def image(contenu: bytes, media_type: str = "image/png") -> dict:
    return {"fichier": {"media_type": media_type, "donnees_base64": base64.b64encode(contenu).decode()}}


def test_a_file_that_is_not_an_image_never_reaches_the_extractor(client, extracteur):
    reponse = client.post("/v1/extractions", json=image(b"pas une image"), headers=AUTH)
    assert reponse.status_code == 422
    assert "image" in reponse.json()["detail"]
    assert extracteur.appels == []


def test_an_images_real_type_wins_over_the_declared_one(client, extracteur):
    jpeg = b"\xff\xd8\xff\xe0 reste"
    assert client.post("/v1/extractions", json=image(jpeg), headers=AUTH).status_code == 200
    assert extracteur.appels[0][0].media_type == "image/jpeg"


def test_one_address_cycling_fresh_accounts_gets_a_429(extracteur):
    client = client_avec(extracteur, requetes_par_minute_ip=2, entete_ip="True-Client-IP")
    ip = {"True-Client-IP": "203.0.113.7"}
    for i in range(2):
        entetes = {"Authorization": f"Bearer ok-anonyme-{i}", **ip}
        assert client.post("/v1/extractions", json=COURRIER, headers=entetes).status_code == 200
    bloque = {"Authorization": "Bearer ok-anonyme-9", **ip}
    assert client.post("/v1/extractions", json=COURRIER, headers=bloque).status_code == 429
    ailleurs = {"Authorization": "Bearer ok-anonyme-9", "True-Client-IP": "198.51.100.1"}
    assert client.post("/v1/extractions", json=COURRIER, headers=ailleurs).status_code == 200


def test_ipv6_clients_are_counted_by_their_64_prefix(extracteur):
    client = client_avec(extracteur, requetes_par_minute_ip=1, entete_ip="True-Client-IP")
    premier = {**AUTH, "True-Client-IP": "2001:db8:1:2::1"}
    assert client.post("/v1/extractions", json=COURRIER, headers=premier).status_code == 200
    voisin = {"Authorization": "Bearer ok-bob", "True-Client-IP": "2001:db8:1:2:ffff::9"}
    assert client.post("/v1/extractions", json=COURRIER, headers=voisin).status_code == 429


def test_daily_limit_per_address(extracteur):
    client = client_avec(extracteur, requetes_par_jour_ip=1, entete_ip="True-Client-IP")
    ip = {"True-Client-IP": "203.0.113.7"}
    assert client.post("/v1/extractions", json=COURRIER, headers={**AUTH, **ip}).status_code == 200
    autre = {"Authorization": "Bearer ok-bob", **ip}
    reponse = client.post("/v1/extractions", json=COURRIER, headers=autre)
    assert reponse.status_code == 429
    assert "demain" in reponse.json()["detail"]


def test_a_missing_proxy_header_leaves_the_other_limits_and_is_logged(extracteur, capsys):
    client = client_avec(extracteur, requetes_par_minute_ip=1, entete_ip="True-Client-IP")
    for nom in ("alice", "bob"):
        entetes = {"Authorization": f"Bearer ok-{nom}"}
        assert client.post("/v1/extractions", json=COURRIER, headers=entetes).status_code == 200
    assert journal_extraction(capsys)["ip"] == "absente"


def test_the_address_is_never_logged(extracteur, capsys):
    client = client_avec(extracteur, entete_ip="True-Client-IP")
    client.post("/v1/extractions", json=COURRIER, headers={**AUTH, "True-Client-IP": "203.0.113.7"})
    sortie = capsys.readouterr().out
    assert "203.0.113" not in sortie
    assert '"ip": "connue"' in sortie


def test_a_client_cannot_pick_its_address_through_another_header(extracteur):
    client = client_avec(extracteur, requetes_par_minute_ip=1, entete_ip="True-Client-IP")
    ip = {"True-Client-IP": "203.0.113.7"}
    assert client.post("/v1/extractions", json=COURRIER, headers={**AUTH, **ip}).status_code == 200
    ruse = {"Authorization": "Bearer ok-bob", "X-Forwarded-For": "198.51.100.1", **ip}
    assert client.post("/v1/extractions", json=COURRIER, headers=ruse).status_code == 429
