# HANDOFF — Pli
Reads an administrative letter and turns it into a deadline. Prototype for a job application to Buddy (full-stack & AI
work-study). Updated 2026-11-09.

## Next step
1. **Deploy (Falek, blocked for Claude: the auto mode denies production deploys):** `main` (c860578, PRs #22–#24) is
   merged but **not live**: Render Auto-Deploy did not fire again. Render: Manual Deploy → latest commit (service `pli`),
   or allow `mcp__claude_ai_Render__trigger_deploy`. Then the web app (build + `vercel deploy --prod`, see `app/CLAUDE.md`).
2. **Live tests after the deploy:** `/healthz` 200, forged token 401, startup log without the `PLI_ENTETE_IP` WARNING;
   Falek does one real reading with a fictional letter (reload, « Saisir à la main »), then the Render log of that
   reading must say `"ip": "connue"`. **Spoofing probe** (one paid reading, needs a valid App Check token, so from a real
   session or the iOS debug token): send `True-Client-IP: pas-une-ip`; log `"ip": "absente"` means the client's header
   passes through, then switch to `CF-Connecting-IP`; `"connue"` means Cloudflare overwrites it. On the live app also
   check the account menu: notice, « Supprimer mes données » with a throwaway anonymous list.
3. **iPhone:** Codemagic build of `main`, Sideloadly, try the 3 import options and « Supprimer mes données » with Google.
   If it passes: remove the diagnostics in `lecteur_courrier.dart` and `session.dart` (branch + PR); Falek revokes the
   `Codemagic iOS test` token, deletes the Codemagic variable and every IPA copy (including
   `C:\Users\falek\Downloads\Pli-unsigned.ipa`: the token is readable inside), restricts the iOS key to `fr.pli.pli`.
4. Falek confirms the notice's contact (`contactConfidentialite` in `confidentialite.dart` = his Gmail).

## State
All PRs merged (#1–#25). **Live = #21** until the deploy in Next step 1: the account menu, add sheet, privacy notice,
data deletion and per-IP limit (PRs #22–#24) are on `main` only.
- **Real app: https://pli-app-flame.vercel.app** (Vercel `pli-app`, deployed by hand). Firebase `plii-ba3d8` on Spark
  (anonymous + Google sign-in, Firestore europe-west9). Backend on **Render free** (https://pli-rif0.onrender.com, Docker
  from `main`, sleeps after 15 min, ~1 min to wake). Render env: `ANTHROPIC_API_KEY`, `PLI_PROJET_FIREBASE=plii-ba3d8`,
  `PLI_ORIGINES_CORS=https://pli-app-flame.vercel.app`, `PLI_REQUETES_PAR_MINUTE_INSTANCE=20`, `PLI_APP_CHECK=1`,
  `PLI_ENTETE_IP=True-Client-IP`.
- **Demo: https://pli-demo.vercel.app** (`PLI_DEMO=true`: no Firebase, no backend, 3 sample letters).
- **iOS test build:** Codemagic unsigned IPA + Sideloadly (no Mac, free Apple ID, 7 days, bundle `fr.pli.pli`). iOS now
  calls the backend through `cupertino_http`, after `Failed host lookup` with dart:io (root cause never found).
- **Spend:** Anthropic has 5 € prepaid with no auto top-up. That is the real spend cap; nothing warns when it runs out.
- **Local, never pushed:** `.claude/hooks/verify.sh`, `.github/workflows/ci.yml` (the GitHub token lacks the `workflow`
  scope), `audits/` (public repo: never commit it).

## Verified / not verified
- **Last checks (merged `main` c860578, 2026-11-09):** backend ruff + 140, rule eval 0 late / 0 silent, app format +
  analyze + 153, rules 29/29, web release build. Emulator E2E of data deletion (anonymous at 1440 and 390, Google with
  re-auth) on 2026-11-08. Not run on main: the earlier 1440/390 E2E of reading and saving.
- **Live, without a real reading:** POST without or with a forged token 401, `/healthz` 200 (`claude`), `/docs` 404, hostile
  preflight 400, security headers present, bundle contains « Saisir ».
- **Not verified:** native flows on current code, a real reading on live, real Anthropic responses and billing (5 MB base64
  limit, message when credit is empty), memory on Render, why Render Auto-Deploy (on, on commit) did not deploy PRs #21 and #24.
- **Eval:** rules 10/10, 14/14, 12/12, 7/15 unseen (1 silent error); Opus 5.5 51/51 on 2026-10-30, not rerun since
  `messages.parse` and the look-alike fix. Tables in the README.

## Decisions
- Zero data retention with Anthropic: not now (Falek, 2026-11-09). The notice states the 30-day deletion instead.
- Fictional example letters are demo-only: on the real app each one was a paid reading.
- `max_tokens` stays at 16000 for now: lowering it requires a paid eval.
- No chat version: Pli keeps its own behaviour (a chat would come later, inside Buddy's agent).
- Accepted: Spark quota or instance cap can be filled by token holders, counters in memory, malformed
  provider 200 returns 500, spinner with text on an offline first start.

## Later
- A merged anonymous list stays in Firestore, unreachable (`_fusionnerVers`): erased on request; a retention rule would
  remove it (cloud change, Falek's go).
- Falek: `workflow` scope to push the CI, branch protection, Dependabot. REL-003, Android (DEBT-002), Firebase majors
  (DEBT-003). Report: `audits/AUDIT-2026-11-05.md`.
- Optional: paid Claude eval (ask first), Render Auto-Deploy, GitLab mirror, 30 s video.
- Not built: push reminders.

## Gotchas
- Vercel: `vercel link` inside this repo connects GitHub and every push then deploys the raw repo (404). Both projects are
  disconnected; after any new link run `vercel git disconnect --yes`. Vercel links: `app/build/*/.vercel`.
- A new app domain goes into the web key's referrers, Auth authorized domains and the reCAPTCHA key.
- A failed Codemagic log could expose `DART_DEFINES`:
  check it, revoke the token if so.
- Emulator mode on web: a page reload sends Auth to production (session restored before `useAuthEmulator`): no reload
  in E2E scripts.
- Web emoji (📬 🏠 ⚡ 🏆) render black and white (CanvasKit fallback); two fixes tried, none worked.
