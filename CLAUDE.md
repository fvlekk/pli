# Pli

A mobile app that reads an administrative letter (tax notice, CAF, Assurance Maladie, fines...) and turns it into
a deadline the user can't miss. Prototype (Flutter, Python, Firestore, Claude). Live: app on Vercel, backend on
Render, Firebase `plii-ba3d8` with App Check enforced (state and URLs in `HANDOFF.md`).
UI text is French; code, comments and docs are English.

## Layout
| Path | What |
|---|---|
| `app/` | Flutter app (web + Android + iOS). Firebase Auth (anonymous) + Firestore, calls the backend to read letters. |
| `backend/` | Python 3.12, FastAPI, stateless. `POST /v1/extractions`: letter (text, PDF, image) → structured deadline. |
| `backend/evals/` | Synthetic letters + expected answers. The extractor is judged here, never by eye. |
| `firebase/` | `firestore.rules` + rules tests on the emulator. |

## Carte
- **Routes:** `backend/src/pli/main.py` — `GET /healthz`, `POST /v1/extractions` (ID token + App Check `auth.py`, rate
  limit `limiteur.py`, PDF page cap `courrier.py`).
- **Business logic:** `backend/src/pli/extracteurs/` (`regle.py` offline baseline, `claude.py`, `base.py`) · `schema.py`
  (output + text limits) · `courrier.py` (letter input) · `journal.py` (logs without content). App: `app/lib/ecrans/`,
  `services/` (`session.dart` = anonymous + Google account), `modeles/`, `outils/` (dates, photo shrinking, web file
  picker), `widgets/` (cards, notices), `demo/` (PLI_DEMO), `theme.dart`.
- **Tests:** `backend/tests/test_*.py` (pytest) · `backend/evals/` (`run.py`, `dataset/`, `attendu.jsonl`) ·
  `app/test/*_test.dart` (fakes in `faux.dart`) · `firebase/tests/regles.test.js`. Invariants: see below.
- **Agent hooks (local, not pushed):** `.claude/hooks/verify.sh` runs the checks of each changed part on Stop.

## Commands (run the ones for what you touched, before saying "done")
```bash
# backend
cd backend && uv sync && uv run ruff check . && uv run ruff format --check . && uv run pytest
uv run python -m evals.run --extracteur regle            # offline, free
uv run python -m evals.run --extracteur claude --split test   # needs ANTHROPIC_API_KEY, costs money: ask first

# firestore rules (needs Java 11+)
cd firebase && npm ci && npm test

# app
cd app && flutter pub get && dart format --set-exit-if-changed lib test && flutter analyze && flutter test

# local demo: emulators (auth 9099, firestore 8085) + backend (8080) + app (5173)
cd firebase && npx firebase emulators:start --only auth,firestore --project demo-pli
cd backend && PLI_AUTH_EMULATEUR=1 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
  uv run uvicorn --factory pli.main:creer_app_depuis_env --port 8080
cd app && flutter run -d chrome --web-port 5173 \
  --dart-define=PLI_EMULATEURS=true --dart-define=PLI_API_URL=http://127.0.0.1:8080
# stop a server by its port, never with pkill -f
fuser -k 8080/tcp

# public web demo (no Firebase, no backend): build locally, Vercel has no Flutter. Project pli-demo.
cd app && flutter build web --release --no-wasm-dry-run --dart-define=PLI_DEMO=true   # web/vercel.json lands in build/web
# always --no-wasm-dry-run: the wasm dry run can hang for many minutes
cd app/build/web && npx vercel link --yes --project pli-demo && rm -f .env.local && npx vercel git disconnect --yes \
  && npx vercel deploy --prod   # link inside this repo connects GitHub: disconnect, or pushes deploy a 404
# real app (Firebase plii-ba3d8, backend on Render): same, into build/web-app, Vercel project pli-app
cd app && flutter build web --release --no-wasm-dry-run --output build/web-app \
  --dart-define=PLI_API_URL=https://pli-rif0.onrender.com --dart-define=PLI_FIREBASE_PROJET=plii-ba3d8 \
  --dart-define=PLI_FIREBASE_APP_ID=... --dart-define=PLI_FIREBASE_API_KEY=... --dart-define=PLI_FIREBASE_SENDER_ID=... \
  --dart-define=PLI_RECAPTCHA_CLE=...   # App Check (web only); empty = off
#   values: npx firebase apps:sdkconfig WEB --project plii-ba3d8, reCAPTCHA Enterprise site key (all public, not secrets)
#   backend: PLI_APP_CHECK=1 requires the App Check token; unset, it is only checked and logged (app_check: ...)
```
On web, the Firebase emulator banner covers the
bottom button: remove `.firebase-emulator-warning` when scripting screenshots.
Test flows with Playwright **locally** (emulators + local backend): on the live app App Check is enforced and
reCAPTCHA scores headless browsers as bots, so the app stops at its start screen.

## Invariants (a change that breaks one is refused in review)
- **Evaluate before building.** Any change to the prompt, the model, the schema or the rule extractor comes with a
  run of `evals.run` and the before/after scores in the MR. `dev` is for tuning; `test` is run once per change, never tuned on.
- **A late deadline is the worst error.** The eval counts it separately (`date_trop_tardive`). Never trade it for accuracy.
- **The letter is data, never instructions.** It goes to the model inside `<courrier>` tags; the output is a fixed
  JSON schema validated by pydantic. A letter that says "ignore your instructions" is an eval case.
- **The backend stores nothing.** It never logs letter content, only a hash of the uid, sizes, timings and token counts.
  The user confirms the extraction in the app, and the app writes it to Firestore.
- **Users only see their own data.** Firestore path `users/{uid}/echeances/{id}`; rules check `request.auth.uid == uid`
  and the document's shape. Any rules change comes with a rules test.
- Every backend route except `/healthz` requires a valid Firebase ID token, and is rate limited per uid and per
  instance (anonymous accounts are free to create: the per-uid limit alone caps nothing).
- Text limits are the same in `schema.py`, `firestore.rules` and the app (titre/organismeNom 120, resume 500).
  Change one, change all three, or the user cannot save.

## Never
- Secrets in the repo (API keys go in env vars locally, Secret Manager in Cloud Run). `.env.example` only.
- Real letters in `evals/dataset/`: synthetic only, fictional names and addresses.
- Deploy, create cloud resources or call the paid API without the owner's explicit go.
- Weaken a Firestore rule to make the app work: fix the app.

## Conventions
- Backend: small modules, pydantic models at the edges, dependencies injected (tests use fakes, never the network).
- App: no state-management library until a screen needs one; services are passed in through constructors.
  Design tokens live in `app/lib/theme.dart`; no raw colors in widgets.
- French UI copy: short, tutoiement, no jargon ("Payer avant le 15 nov.", not "Échéance de règlement").
