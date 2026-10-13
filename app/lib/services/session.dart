import 'package:firebase_auth/firebase_auth.dart';

/// Anonymous Firebase session: no sign-up wall before the first letter. Linking an email comes later.
class Session {
  Session(this._auth);

  final FirebaseAuth _auth;

  Future<void> ouvrir() async {
    if (_auth.currentUser == null) await _auth.signInAnonymously();
  }

  String get uid => _auth.currentUser!.uid;

  Future<String> jeton() async => (await _auth.currentUser!.getIdToken())!;
}
