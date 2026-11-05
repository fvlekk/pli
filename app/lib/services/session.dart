import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config.dart';

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
  Session(this._auth, {this._jetonGoogle = _jetonGoogleNatif});

  final FirebaseAuth _auth;

  /// Google's ID token on iOS; null when the user closed the Google window.
  final Future<String?> Function() _jetonGoogle;

  /// `initialize` must run only once, and the user can try again after closing the window.
  static Future<void>? _initialisationGoogle;

  static Future<void> _initialiserGoogle() async {
    try {
      await (_initialisationGoogle ??= GoogleSignIn.instance.initialize());
    } catch (_) {
      _initialisationGoogle = null; // A kept failure would make every retry fail until the app restarts.
      rethrow;
    }
  }

  static Future<String?> _jetonGoogleNatif() async {
    try {
      await _initialiserGoogle();
      final compte = await GoogleSignIn.instance.authenticate();
      return compte.authentication.idToken ?? (throw _echecGoogle('no-id-token'));
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw _echecGoogle(e.code.name);
    } on PlatformException catch (e) {
      // Google's SDK reports some native failures outside the plugin's own exception.
      throw _echecGoogle(e.code);
    }
  }

  static CompteImpossible _echecGoogle(String code) {
    // Temporary, iOS test builds only: this message hides why the sign-in fails on the phone.
    final detail = Config.jetonDebugAppCheck.isEmpty ? '' : ' [$code]';
    return CompteImpossible('Connexion Google impossible pour le moment. Réessaie.$detail');
  }

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
      // iOS: Firebase's web page loses its state in the browser ("missing initial state"), so Google's SDK signs in.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) return await _garderSurIos(listeVide: listeVide);
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
        'popup-closed-by-user' ||
        'cancelled-popup-request' ||
        'web-context-canceled' ||
        'web-context-cancelled' => ResultatGoogle.annule,
        // Both lists hold deadlines: never merge or drop one silently.
        'credential-already-in-use' || 'email-already-in-use' => throw const CompteImpossible(
          'Ce compte Google a déjà sa propre liste. Pli ne fusionne pas encore deux listes : '
          'utilise un autre compte Google, ou supprime d\'abord les échéances de cet appareil.',
        ),
        'popup-blocked' => throw const CompteImpossible(
          'Ton navigateur a bloqué la fenêtre Google : autorise les fenêtres pour ce site, puis réessaie.',
        ),
        _ => throw _echecGoogle(e.code),
      };
    }
  }

  Future<ResultatGoogle> _garderSurIos({required bool listeVide}) async {
    final jeton = await _jetonGoogle();
    if (jeton == null) return ResultatGoogle.annule;
    final identifiants = GoogleAuthProvider.credential(idToken: jeton);
    if (listeVide) {
      await _auth.signInWithCredential(identifiants);
      return ResultatGoogle.connecte;
    }
    await _auth.currentUser!.linkWithCredential(identifiants);
    return ResultatGoogle.relie;
  }
}
