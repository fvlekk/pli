# HANDOFF — Pli

## Why this repo exists
Prototype on a Flutter, Python, Firestore, Google Cloud, GitLab CI and Claude Code stack, built for a job
application to Buddy (full-stack & AI work-study role).

## State (2026-11-02)
- **Real app live: https://pli-app-flame.vercel.app** (Vercel project `pli-app`), checked end to end on
  2026-11-02: a sample letter read by Claude, checked, saved to Firestore, shown on the home screen.
  Firebase project `plii-ba3d8` on the free Spark plan (anonymous auth, Firestore in europe-west9, rules
  deployed). Backend on **Render free** (https://pli-rif0.onrender.com, branch `main`, Docker, sleeps after
  15 min, ~1 min to wake up): Google Cloud billing could not be set up (payment refused), so no Cloud Run.
  Render env: `ANTHROPIC_API_KEY` (set by Falek in Render), `PLI_PROJET_FIREBASE=plii-ba3d8`,
  `PLI_ORIGINES_CORS=https://pli-app-flame.vercel.app`, `PLI_REQUETES_PAR_MINUTE_INSTANCE=20`.
  **No App Check yet**: keep the app URL private, rely on the Anthropic monthly cap.
- **Web demo live: https://pli-demo.vercel.app** (Vercel project `pli-demo`). Flag `PLI_DEMO=true`: no Firebase, no backend. `app/lib/demo/` holds an in-memory store (3 made-up deadlines: late,
  this week, this month) and a reader that answers the 3 sample letters only. App: 33 tests, analyzer clean;
  every demo screen checked at 390 px. The bill reads 11 Nov (« avant le 12 » = X−1, the rule of
  `feat/eval-convention-sonnet-new-letters`).
- **Buddy restyle applied (2026-11-01)**: `pli-style-buddy.patch` (Baloo 2, coral, cards, pills, lilac « À FAIRE EN
  PREMIER » card; postmark, folded sheet and stamp animation removed; `messages.parse`; simpler rate limiter).
  Its Dart had never compiled: fixed a pill-row overflow on large text and an ambiguous test finder.
  The Claude eval was not rerun after the `messages.parse` change (paid API, no go).
- **Works locally, end to end**: emulators + backend + Flutter web. Read a sample letter, check it, save it
  to Firestore, and see it on the home screen. Verified with Playwright screenshots (`docs/captures/`).
- Backend: 62 pytest, ruff clean. Firestore rules: 27 tests on the emulator. App: 33 tests, analyzer clean.
- Independent review (reviewer agent) done on 2026-10-12: every finding verified in the code, then fixed with a
  test (list in README « What review caught »).
- Eval: the rule extractor scores 9/10 on `dev` and 6/14 on `test`, with 1 silent error (an Urssaf reminder).
  **The Claude extractor has never run against the real API** (no key here). Its tests use a fake client.
- Not verified: the GitLab CI never ran on GitLab (the GitHub Actions copy of it runs on every PR), the PDF/photo paths were never sent to the API, and nothing ran on a real
  Android/iOS device (web only).
- On GitHub (public): `main` starts empty, the prototype comes in through the first pull request.

## Next step
0. Before sharing the real app (e.g. with Buddy): Firebase App Check verified by the backend.
1. With an Anthropic key: `cd backend && uv run python -m evals.run --extracteur claude --split test` (~14 calls).
   Paste the scores into the README table, then compare `PLI_EFFORT=low` against `medium`.
2. Mirror to GitLab so `.gitlab-ci.yml` runs too (the stack Buddy uses).
3. Record the 30 s motion video from the real screens.

## À confirmer / open
- npm audit: 17 findings, all in dev tooling (firebase-tools, emulator test libs). The "fixes" are downgrades
  to old majors, so they are not applied. Nothing from them ships in the app or the backend.
- Rate limiting is in memory: per uid + an instance-wide cap (60/min by default), times `--max-instances`.
  **Before any public launch: Firebase App Check verified by the backend** (anonymous uids are free to create).
- The model provider keeps API inputs under its own retention policy: production needs a zero-data-retention
  agreement and a privacy notice that says so. The app copy only claims that *Pli* does not store the letter.
- Reminders (FCM push at D-7 / D-1) are not built: today the app is the reminder.
- Rule extractor titles are generic (« Payer (amende) »). Claude writes real ones.
- Web only: some emoji (📬, 🏠, ⚡, 🏆) render black and white, because Flutter's CanvasKit falls back to a
  symbols font for them. Neither `fontFamilyFallback: ['Noto Color Emoji']` nor U+FE0F fixed it. Native
  Android/iOS use the system color emoji.
- Vercel: `vercel link` run from a folder inside this repo connects the GitHub repo to the project, and every
  push to `main` then deploys the raw repo (no Flutter build) over the app: both sites served 404 on
  2026-11-02. Both projects are now disconnected (`vercel git disconnect`); redo it after any new link.
- The live Claude reading gives « avant le 12/11 » as 12 Nov: the X−1 rule is only on the unmerged
  `feat/eval-convention-sonnet-new-letters`.
