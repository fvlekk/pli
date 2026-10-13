# Pli

A mobile app that reads an administrative letter (tax notice, CAF, Assurance Maladie, fines...) and turns it into
a deadline the user can't miss. Prototype (Flutter, Python, Firestore, Google Cloud).
UI text is French; code, comments and docs are English.

## Layout
| Path | What |
|---|---|
| `app/` | Flutter app (web + Android + iOS). Firebase Auth (anonymous) + Firestore, calls the backend to read letters. |
| `backend/` | Python 3.12, FastAPI, stateless. `POST /v1/extractions`: letter (text, PDF, image) → structured deadline. |
| `backend/evals/` | Synthetic letters + expected answers. The extractor is judged here, never by eye. |
| `firebase/` | `firestore.rules` + rules tests on the emulator. |

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
```
On web, the Firebase emulator banner covers the
bottom button: remove `.firebase-emulator-warning` when scripting screenshots.

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
