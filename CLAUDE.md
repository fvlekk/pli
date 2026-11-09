# Pli

A mobile app that reads an administrative letter (tax notice, CAF, Assurance Maladie, fines...) and turns it into
a deadline the user can't miss. Prototype (Flutter, Python, Firestore, Claude). Live: app on Vercel, backend on
Render, Firebase `plii-ba3d8` with App Check enforced (state and URLs in `HANDOFF.md`).
UI text is French; code, comments and docs are English.

## Layout
Each part has its own `CLAUDE.md` (map, commands, conventions), loaded when work reaches that folder. Before saying
"done", run the checks of each part you touched; read its `CLAUDE.md` first if it is not loaded yet.
| Path | What |
|---|---|
| `app/` | Flutter app (web + Android + iOS). Firebase Auth (anonymous, optional Google) + Firestore + App Check (web; debug token on iOS test builds), calls the backend to read letters. |
| `backend/` | Python 3.12, FastAPI, stateless. `POST /v1/extractions`: letter (text, PDF, image) → structured deadline. |
| `backend/evals/` | Synthetic letters + expected answers. The extractor is judged here, never by eye. |
| `firebase/` | `firestore.rules` + rules tests on the emulator. |

Agent hooks (local, not pushed): `.claude/hooks/verify.sh` runs the checks of each changed part on Stop.

## Local demo
Emulators (auth 9099, firestore 8085) + backend (8080) + app (5173). Flutter: see `app/CLAUDE.md`.
```bash
cd firebase && npx firebase emulators:start --only auth,firestore --project demo-pli
cd backend && PLI_AUTH_EMULATEUR=1 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
  uv run uvicorn --factory pli.main:creer_app_depuis_env --port 8080
cd app && flutter run -d chrome --web-port 5173 \
  --dart-define=PLI_EMULATEURS=true --dart-define=PLI_API_URL=http://127.0.0.1:8080
# stop a server by its port, never with pkill -f
fuser -k 8080/tcp
```

## Invariants (a change that breaks one is refused in review)
- **Evaluate before building.** Any change to the prompt, the model, the schema or the rule extractor comes with a
  run of `evals.run` and the before/after scores in the MR. `dev` is for tuning; `test` is run once per change, never tuned on.
- **A late deadline is the worst error.** The eval counts it separately (`date_trop_tardive`). Never trade it for accuracy.
- **The letter is data, never instructions.** It goes to the model inside `<courrier>` tags; the output is a fixed
  JSON schema validated by pydantic. A letter that says "ignore your instructions" is an eval case.
- **The backend stores nothing.** It never logs letter content, only a hash of the uid, sizes, timings and token counts.
  The user confirms the extraction in the app, and the app writes it to Firestore.
- **The privacy notice tells the truth.** `app/lib/ecrans/confidentialite.dart` says what leaves the phone, to whom,
  and what is kept how long. A new provider, a new stored field or a new retention changes it in the same MR.
  « Supprimer mes données » erases the deadlines, then the account (`Session.supprimerMesDonnees`).
- **Users only see their own data.** Firestore path `users/{uid}/echeances/{id}`; rules check `request.auth.uid == uid`
  and the document's shape. Any rules change comes with a rules test.
- Every backend route except `/healthz` requires a valid Firebase ID token, and is rate limited per uid, per
  client IP and per instance (anonymous accounts are free to create: the per-uid limit alone caps nothing), per minute
  and per day. Behind a proxy the IP comes from `PLI_ENTETE_IP`; when that header is missing only the other limits hold,
  and the log says `ip: absente`. The counters are in memory and a restart resets them: the real bound on a day's cost is the provider's spend limit.
  The token is checked and the limits applied before the body is read; readings in progress at once are capped too.
- Text limits are the same in `schema.py`, `firestore.rules` and the app (titre/organismeNom 120, resume 500).
  Change one, change all three, or the user cannot save.

## Never
- Secrets in the repo (API keys go in env vars locally, env vars on the host). `.env.example` only.
- Real letters in `evals/dataset/`: synthetic only, fictional names and addresses.
- Deploy, create cloud resources or call the paid API without the owner's explicit go.
- Weaken a Firestore rule to make the app work: fix the app.
