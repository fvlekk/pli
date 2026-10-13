# HANDOFF — Pli

## Why this repo exists
Prototype on a Flutter, Python, Firestore, Google Cloud, GitLab CI and Claude Code stack, built for a job
application to Buddy (full-stack & AI work-study role).

## State (2026-10-12)
- **Works locally, end to end**: emulators + backend + Flutter web. Read a sample letter, check it, save it
  to Firestore, and see it in the folded-letter home. Verified with Playwright screenshots (`docs/captures/`).
- Backend: 62 pytest, ruff clean. Firestore rules: 27 tests on the emulator. App: 27 tests, analyzer clean.
- Independent review (reviewer agent) done on 2026-10-12: every finding verified in the code, then fixed with a
  test (list in README « What review caught »).
- Eval: the rule extractor scores 9/10 on `dev` and 6/14 on `test`, with 1 silent error (an Urssaf reminder).
  **The Claude extractor has never run against the real API** (no key here). Its tests use a fake client.
- Not verified: the GitLab CI never ran on GitLab (the GitHub Actions copy of it runs on every PR), the PDF/photo paths were never sent to the API, and nothing ran on a real
  Android/iOS device (web only).
- On GitHub (public): `main` starts empty, the prototype comes in through the first pull request.

## Next step
1. With an Anthropic key: `cd backend && uv run python -m evals.run --extracteur claude --split test` (~14 calls).
   Paste the scores into the README table, then compare `PLI_EFFORT=low` against `medium`.
2. Mirror to GitLab so `.gitlab-ci.yml` runs too (the stack Buddy uses).
3. Record the 30 s motion video from the real screens: the postmark landing (`CoupDeTampon`) is the hero shot.

## À confirmer / open
- npm audit: 17 findings, all in dev tooling (firebase-tools, emulator test libs). The "fixes" are downgrades
  to old majors, so they are not applied. Nothing from them ships in the app or the backend.
- Rate limiting is in memory: per uid + an instance-wide cap (60/min by default), times `--max-instances`.
  **Before any public launch: Firebase App Check verified by the backend** (anonymous uids are free to create).
- The model provider keeps API inputs under its own retention policy: production needs a zero-data-retention
  agreement and a privacy notice that says so. The app copy only claims that *Pli* does not store the letter.
- Reminders (FCM push at D-7 / D-1) are not built: today the app is the reminder.
- Rule extractor titles are generic (« Payer (amende) »). Claude writes real ones.
