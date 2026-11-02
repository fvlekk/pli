import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// What happened when the user asked to keep their deadlines with Google.
enum ResultatGoogle {
  /// The anonymous account is now linked to Google: same account, every deadline kept.
  relie,

  /// This device's list was empty: the app now shows the Google account's own list (from another phone).
  connecte,

  /// The user closed the Google window.
  annule,
}

/// A failure the user can act on; `message` is shown as is.
class CompteImpossible implements Exception {
  const CompteImpossible(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The user's account as the screens see it (a fake in tests, nothing in the demo).
abstract interface class Compte {
  bool get estAnonyme;
  String? get email;

  /// `listeVide`: nothing to keep on this device, so an existing Google list can simply be opened.
  Future<ResultatGoogle> garderAvecGoogle({required bool listeVide});
}

/// Anonymous Firebase session: no sign-up wall before the first letter. Google comes when the user wants to keep
/// the list across phones.
class Session implements Compte {
  Session(this._auth);

  final FirebaseAuth _auth;

  Future<void> ouvrir() async {
    if (_auth.currentUser == null) await _auth.signInAnonymously();
  }

  String get uid => _auth.currentUser!.uid;

  Future<String> jeton() async => (await _auth.currentUser!.getIdToken())!;

  @override
  bool get estAnonyme => _auth.currentUser?.isAnonymous ?? true;

  @override
  String? get email => _auth.currentUser?.email;

  @override
  Future<ResultatGoogle> garderAvecGoogle({required bool listeVide}) async {
    final google = GoogleAuthProvider();
    try {
      if (listeVide) {
        // Nothing to keep here: open the Google account's list, new or from another phone.
        kIsWeb ? await _auth.signInWithPopup(google) : await _auth.signInWithProvider(google);
        return ResultatGoogle.connecte;
      }
      final utilisateur = _auth.currentUser!;
      kIsWeb ? await utilisateur.linkWithPopup(google) : await utilisateur.linkWithProvider(google);
      return ResultatGoogle.relie;
    } on FirebaseAuthException catch (e) {
      return switch (e.code) {
        'popup-closed-by-user' || 'cancelled-popup-request' || 'web-context-canceled' => ResultatGoogle.annule,
        // Both lists hold deadlines: never merge or drop one silently.
        'credential-already-in-use' || 'email-already-in-use' => throw const CompteImpossible(
          'Ce compte Google a déjà sa propre liste. Pli ne fusionne pas encore deux listes : '
          'utilise un autre compte Google, ou supprime d\'abord les échéances de cet appareil.',
        ),
        'popup-blocked' => throw const CompteImpossible(
          'Ton navigateur a bloqué la fenêtre Google : autorise les fenêtres pour ce site, puis réessaie.',
        ),
        _ => throw const CompteImpossible('Connexion Google impossible pour le moment. Réessaie.'),
      };
    }
  }
}
