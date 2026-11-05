import 'package:firebase_core/firebase_core.dart';

/// Build-time settings, passed with --dart-define. Nothing secret in the source: a Firebase web API key is a
/// public identifier, access is enforced by firestore.rules and by the backend's token check.
abstract final class Config {
  static const emulateurs = bool.fromEnvironment('PLI_EMULATEURS');

  /// Public web demo: no Firebase, no backend. Deadlines live in memory and only the sample letters are read.
  static const demo = bool.fromEnvironment('PLI_DEMO');

  /// Public reCAPTCHA Enterprise site key (score) for App Check on the web. Empty: App Check off (local runs,
  /// emulators).
  static const cleRecaptcha = String.fromEnvironment('PLI_RECAPTCHA_CLE');

  /// App Check debug token for a personal iOS test build: free Apple accounts cannot use App Attest. It lets its
  /// holder pass App Check, so it stays in the build service's secrets, and it is revoked after the test. Empty: off.
  static const jetonDebugAppCheck = String.fromEnvironment('PLI_APP_CHECK_JETON_DEBUG');

  /// 127.0.0.1 for web and iOS simulator, 10.0.2.2 for the Android emulator.
  static const hoteEmulateurs = String.fromEnvironment('PLI_HOTE_EMULATEURS', defaultValue: '127.0.0.1');

  static final urlApi = Uri.parse(const String.fromEnvironment('PLI_API_URL', defaultValue: 'http://127.0.0.1:8080'));

  static const optionsFirebase = FirebaseOptions(
    apiKey: String.fromEnvironment('PLI_FIREBASE_API_KEY', defaultValue: 'demo-cle'),
    appId: String.fromEnvironment('PLI_FIREBASE_APP_ID', defaultValue: '1:000000000000:web:0000000000000000'),
    messagingSenderId: String.fromEnvironment('PLI_FIREBASE_SENDER_ID', defaultValue: '000000000000'),
    projectId: _projet,
    // The Google sign-in window runs on the project's Firebase domain.
    authDomain: '$_projet.firebaseapp.com',
  );

  static const _projet = String.fromEnvironment('PLI_FIREBASE_PROJET', defaultValue: 'demo-pli');
}
