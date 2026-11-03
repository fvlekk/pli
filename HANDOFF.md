# HANDOFF — Pli

## Why this repo exists
Prototype for a job application to Buddy (full-stack & AI work-study): Flutter, Python, Firestore, Claude.
Work happens in the worktree `~/projects/pli-demo` (branch `main`). `~/projects/pli` holds the older local branch
`feat/eval-convention-sonnet-new-letters` (uncommitted eval work, older HANDOFF): don't start from there.

## State (2026-11-03) — done, live, nothing open on GitHub (PRs #1–#16 merged)
- **Real app: https://pli-app-flame.vercel.app** (Vercel `pli-app`). Firebase `plii-ba3d8` on Spark (anonymous
  auth + optional Google sign-in, Firestore europe-west9). Backend on **Render free**
  (https://pli-rif0.onrender.com, Docker from `main`; sleeps after 15 min, ~1 min to wake). No Cloud Run: Google
  billing could not be set up. Render env: `ANTHROPIC_API_KEY`, `PLI_PROJET_FIREBASE=plii-ba3d8`,
  `PLI_ORIGINES_CORS=https://pli-app-flame.vercel.app`, `PLI_REQUETES_PAR_MINUTE_INSTANCE=20`, `PLI_APP_CHECK=1`.
- **Demo: https://pli-demo.vercel.app** (Vercel `pli-demo`, `PLI_DEMO=true`: no Firebase, no backend, 3 sample
  letters with prepared readings).
- **Security**: App Check (reCAPTCHA Enterprise key `6LffCQwu…`) enforced on the backend, Firestore and
  Authentication; Firestore rules per user; Firebase web key restricted to the app's referrers and APIs; PDFs capped
  at 10 pages; letters are data (`<courrier>` tags, look-alikes stripped); backend stores and logs no content.
- **Checks**: backend 80 tests, app 52, Firestore rules 27/27 (emulator). Live flows checked: read (Claude), check,
  save, done, undo, delete; photo shrinking and mobile file picking reproduced and fixed.
- **Decision 2026-11-03**: no chat version. Pli keeps its own behaviour; a chat would be built later, inside
  Buddy's agent, if Falek works there.

## Next step
1. Falek: test on his phone (reload first): a PDF, a photo, then « Garder mes échéances avec Google ».
2. Optional, paid (ask first): `cd backend && uv run python -m evals.run --extracteur claude --split test`, scores
   into the README. Never run since `messages.parse` and the look-alike tag fix.
3. Optional: merge the X−1 rule (« avant le 12 » = 11) from `feat/eval-convention-sonnet-new-letters` (in
   `~/projects/pli`): today the live reading says 12 Nov, the demo says 11. Mirror to GitLab; 30 s video.

## Gotchas (cost us time)
- Vercel: never let `vercel link` connect GitHub (the build folders sit inside the repo): every push to `main`
  then deploys the raw repo and both sites serve 404. Both projects are disconnected; redo `vercel git disconnect`
  after any new link. Deploy commands: `CLAUDE.md`.
- `flutter build web` can hang in its wasm dry run: always pass `--no-wasm-dry-run`.
- Since App Check is enforced, reCAPTCHA scores headless Playwright as a bot: automated checks of the **live** app
  stop at « Pli n'arrive pas à démarrer ». Test flows locally with the emulators (`CLAUDE.md`), the live app by hand.
- A new app domain must be added to the Firebase key's referrers, Auth authorized domains and the reCAPTCHA key.
- Web emoji (📬 🏠 ⚡ 🏆) render black and white (CanvasKit font fallback); two fixes tried, none worked.

## Open points
- The model provider keeps API inputs under its own policy: production needs zero data retention and a privacy
  notice. Reminders (push D-7 / D-1) are not built: the app is the reminder. Two lists (device + Google account)
  are never merged: the user is told.
- npm audit: 17 findings in dev tooling only (fixes are downgrades, not applied).
