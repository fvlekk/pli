# Pli app

Flutter is at `~/tools/flutter/bin`, not in PATH: `export PATH="$HOME/tools/flutter/bin:$PATH"`.

## Map
`lib/ecrans/`, `lib/services/` (`session.dart` = anonymous + Google account: popup on web, Google's SDK on iOS; a list moves to an existing Google account by copy, see `_fusionnerVers`; `supprimerMesDonnees` erases deadlines then the account), `lib/ecrans/confidentialite.dart` (privacy notice), `lib/modeles/`, `lib/outils/` (dates, photo
shrinking, web file picker), `lib/widgets/` (cards, notices), `lib/demo/` (PLI_DEMO), `lib/theme.dart`.
Tests: `test/*_test.dart` (fakes in `faux.dart`).

## Commands
```bash
flutter pub get && dart format --set-exit-if-changed lib test && flutter analyze && flutter test

# public web demo (no Firebase, no backend): build locally, Vercel has no Flutter. Project pli-demo.
flutter build web --release --no-wasm-dry-run --dart-define=PLI_DEMO=true   # web/vercel.json lands in build/web
# always --no-wasm-dry-run: the wasm dry run can hang for many minutes
cd build/web && npx vercel link --yes --project pli-demo && rm -f .env.local && npx vercel git disconnect --yes \
  && npx vercel deploy --prod   # link inside this repo connects GitHub: disconnect, or pushes deploy a 404
# real app (Firebase plii-ba3d8, backend on Render): same, into build/web-app, Vercel project pli-app
flutter build web --release --no-wasm-dry-run --output build/web-app \
  --dart-define=PLI_API_URL=https://pli-rif0.onrender.com --dart-define=PLI_FIREBASE_PROJET=plii-ba3d8 \
  --dart-define=PLI_FIREBASE_APP_ID=... --dart-define=PLI_FIREBASE_API_KEY=... --dart-define=PLI_FIREBASE_SENDER_ID=... \
  --dart-define=PLI_RECAPTCHA_CLE=...   # App Check (web only); empty = off
#   values: npx firebase apps:sdkconfig WEB --project plii-ba3d8, reCAPTCHA Enterprise site key (all public, not secrets)

# iOS (no Mac): Codemagic builds an unsigned IPA (`codemagic.yaml`, started by hand, values in its group `pli_ios`),
# Sideloadly installs it from Windows with a free Apple ID (expires after 7 days). Its App Check debug token is for
# personal test builds only: never in the repo, Secure in Codemagic, revoked after the test. It sits in clear in the
# IPA: keep the IPA private. Group values come from `apps:sdkconfig IOS`, not WEB. Not a release path.
```

## Testing flows
On web, the Firebase emulator banner covers the bottom button: remove `.firebase-emulator-warning` when scripting
screenshots. Test flows with Playwright **locally** (emulators + local backend): on the live app App Check is enforced
and reCAPTCHA scores headless browsers as bots, so the app stops at its start screen.

## Conventions
- No state-management library until a screen needs one; services are passed in through constructors.
- Design tokens live in `lib/theme.dart`; no raw colors in widgets.
- `google_sign_in` is used on iOS only, but its web plugin still loads `accounts.google.com/gsi/client` on every web page,
  demo included (Flutter cannot exclude a plugin per platform). Accepted.
- French UI copy: short, tutoiement, no jargon ("Payer avant le 15 nov.", not "Échéance de règlement").
