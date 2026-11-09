# Pli Firestore rules

`firestore.rules` + rules tests in `tests/regles.test.js`, on the emulator. Needs Java 11+.
```bash
npm ci && npm test
```
Any rules change comes with a rules test. Never weaken a rule to make the app work: fix the app.
