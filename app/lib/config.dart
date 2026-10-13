import 'package:firebase_core/firebase_core.dart';

/// Build-time settings, passed with --dart-define. Nothing secret lives here: a Firebase web API key is a
/// public identifier, access is enforced by firestore.rules and by the backend's token check.
abstract final class Config {
  static const emulateurs = bool.fromEnvironment('PLI_EMULATEURS');

  /// 127.0.0.1 for web and iOS simulator, 10.0.2.2 for the Android emulator.
  static const hoteEmulateurs = String.fromEnvironment('PLI_HOTE_EMULATEURS', defaultValue: '127.0.0.1');

  static final urlApi = Uri.parse(const String.fromEnvironment('PLI_API_URL', defaultValue: 'http://127.0.0.1:8080'));

  static const optionsFirebase = FirebaseOptions(
    apiKey: String.fromEnvironment('PLI_FIREBASE_API_KEY', defaultValue: 'demo-cle'),
    appId: String.fromEnvironment('PLI_FIREBASE_APP_ID', defaultValue: '1:000000000000:web:0000000000000000'),
    messagingSenderId: String.fromEnvironment('PLI_FIREBASE_SENDER_ID', defaultValue: '000000000000'),
    projectId: String.fromEnvironment('PLI_FIREBASE_PROJET', defaultValue: 'demo-pli'),
  );
}
