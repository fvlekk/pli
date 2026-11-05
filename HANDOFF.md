# HANDOFF — Pli

## Why this repo exists
Prototype for a job application to Buddy (full-stack & AI work-study): Flutter, Python, Firestore, Claude.
Work in `~/projects/pli` (branch `main`): the only folder. Local, never pushed: `.claude/hooks/verify.sh` and
`.github/workflows/ci.yml` (the GitHub token lacks the `workflow` scope). Vercel links: `app/build/*/.vercel`.

## State (2026-11-03) — done, live, PRs #1–#19 merged, nothing open
- **Real app: https://pli-app-flame.vercel.app** (Vercel `pli-app`). Firebase `plii-ba3d8` on Spark (anonymous
  auth + optional Google sign-in, Firestore europe-west9). Backend on **Render free** (https://pli-rif0.onrender.com,
  Docker from `main`, sleeps after 15 min, ~1 min to wake); no Cloud Run (Google billing refused the card). Render
  env: `ANTHROPIC_API_KEY`, `PLI_PROJET_FIREBASE=plii-ba3d8`, `PLI_ORIGINES_CORS=https://pli-app-flame.vercel.app`,
  `PLI_REQUETES_PAR_MINUTE_INSTANCE=20`, `PLI_APP_CHECK=1`.
- **Demo: https://pli-demo.vercel.app** (`PLI_DEMO=true`: no Firebase, no backend, 3 sample letters).
- **Security**: App Check (reCAPTCHA Enterprise `6LffCQwu…`) enforced on backend, Firestore and Authentication;
  Firestore rules per user; web key restricted to the app's referrers and APIs; PDFs ≤ 10 pages; letters are data
  (`<courrier>` tags, look-alikes stripped); the backend stores and logs no content.
- **Checks**: backend 100 tests, app 52, rules 27/27. Live flows checked (read, check, save, done, undo, delete).
- **Eval**: « avant le X » = X−1, rule extractor rework, held-out `inedit`/`inedit2`. Rules 10/10, 14/14, 12/12,
  **7/15 unseen** (1 silent error); Opus 5.5 51/51 (2026-10-30). Tables in the README.
- **Decision**: no chat version; Pli keeps its own behaviour (a chat would come later, inside Buddy's agent).

## In progress (2026-11-05): native iOS test, branch `feat/ios` (not committed, not built yet)
No Mac and no paid Apple account: Codemagic builds an unsigned IPA, Sideloadly installs it (free Apple ID, 7 days).
Done locally: App Check debug provider on iOS, camera permission, `codemagic.yaml`; analyze clean, 52 app tests pass.
iOS app registered in Firebase (`Pli ios`, `fr.pli.pli`), Google URL schemes in `Info.plist`.
Next, in order: Falek creates the debug token in the console (straight into Codemagic); `reviewer` agent, commit and PR (`.github/` stays out); Codemagic group `pli_ios` and first
build; install, note the bundle ID Sideloadly really uses (a free account may force a suffix) and align the API key
restriction with it (Google sign-in may also need it). After the test: revoke the debug token, delete the Codemagic
secret and the IPA copies (the token is readable inside). Watch: images imported from Files are not shrunk on native
(`image_stub.dart`); a failed build log could expose
`DART_DEFINES`: check it, revoke the token if so.

iOS test status: the app builds, installs with `fr.pli.pli`, starts. Reading failed on Wi-Fi and 4G/5G with
`Failed host lookup` (dart:io's DNS lookup), while Safari reaches the backend and Firebase works: iOS now uses
`cupertino_http` (Apple's URL Loading System). To check on the phone. The cause of the lookup failure itself is not
known. Temporary diagnostic in `lecteur_courrier.dart` shows the real error: remove it after.

## In progress (2026-11-05): audit fixes, branch `fix/audit-2026-11-05` (from `feat/ios`, NOT committed)
Report: `audits/AUDIT-2026-11-05.md` (local only, excluded by `.git/info/exclude`: the repo is public, never commit it).
Fixed: pypdf and other advisories, daily caps, image real type, offline save (no false success, late answer reported,
back blocked), wake on the add screen, web headers, emulator guard on Render, startup warnings, contract test, token and
limits before the body, 4 readings at once, body read timeout, memory released after each reading, manual entry when a
reading fails, no false empty list offline, stale list after an account change, ambiguous amounts refused.
Checks: backend 128, app 94, rules 29, web build and local E2E (1440, 390, Firestore cut) OK, memory under 512 MB locally
with provider errors. Not verified: iOS build, native flows, deployed headers, RSS on Render. Nothing deployed.
Next: Falek's go for commit + push, then Codemagic builds this branch (it needs `cupertino_http` too), reinstall with
Sideloadly, test paste, photo, PDF, save, Google. Then remove the diagnostic, revoke the debug token, delete the
Codemagic variable and the IPA copies (CFG-002), restrict the iOS key (CFG-005), merge, deploy Render and the web app.
Before real use: privacy notice.

## Next step
1. Falek: redeploy Render once (« Deploy latest commit »): the new prompt (X−1 rule, action definitions) is in
   `main` but not live yet.
2. Falek: phone test (reload first): a PDF, a photo, then « Garder mes échéances avec Google ».
3. Optional: paid Claude eval (`evals.run --extracteur claude --split test`, ask first; not run since
   `messages.parse` and the look-alike fix); GitLab mirror; 30 s video.

## Gotchas (cost us time)
- Vercel: `vercel link` inside this repo connects GitHub and every push then deploys the raw repo (404). Both
  projects are disconnected; after any new link run `vercel git disconnect --yes`. Commands: `CLAUDE.md`.
- `flutter build web`: always `--no-wasm-dry-run` (the dry run can hang).
- App Check makes reCAPTCHA score headless Playwright as a bot: test flows locally (emulators), the live app by hand.
- A new app domain goes into the web key's referrers, Auth authorized domains and the reCAPTCHA key.
- Web emoji (📬 🏠 ⚡ 🏆) render black and white (CanvasKit fallback); two fixes tried, none worked.

## Open points
- Production would need zero data retention with the model provider and a privacy notice. Push reminders are not
  built. Device and Google lists are never merged (the user is told). npm audit: dev tooling only.
