import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config.dart';
import '../modeles/echeance.dart';
import 'depot_echeances.dart';

/// What happened when the user chose a Google account.
enum ResultatGoogle {
  /// The anonymous account is now linked to Google: same account, every deadline kept.
  relie,

  /// The app now shows the Google account's own list.
  connecte,

  /// That list is open, and this device's deadlines are being copied to it: see [Compte.finFusion].
  fusionEnCours,

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

  /// From an anonymous session: keeps this device's deadlines, in an existing list if the account has one.
  Future<ResultatGoogle> connecterAvecGoogle();

  /// Opens another Google account's list. The current one stays on its account.
  Future<ResultatGoogle> changerDeCompte();

  Future<void> deconnecter();

  /// True once the copy started by [ResultatGoogle.fusionEnCours] is on the server. Without network it waits. False: it
  /// was refused, and the deadlines exist nowhere else the user can reach.
  Future<bool> finFusion();

  /// Tries a refused copy again: [finFusion] then follows the new attempt.
  void relancerFusion();
}

/// Anonymous Firebase session: no sign-up wall before the first letter. Google comes when the user wants to keep
/// the list across phones.
class Session implements Compte {
  Session(
    this._auth, {
    required this._listeDe,
    this._jetonGoogle = _jetonGoogleNatif,
    this._oublierGoogle = _oublierGoogleNatif,
  });

  /// The deadlines of an account, to copy them from one to the other.
  final ListeDeCompte Function(String uid) _listeDe;

  final FirebaseAuth _auth;

  /// Google's ID token on iOS; null when the user closed the Google window.
  final Future<String?> Function() _jetonGoogle;

  /// Ends the Google SDK's own session on iOS.
  final Future<void> Function() _oublierGoogle;

  /// The copy in progress. shortcut: if the copy is refused, these deadlines only live here, so closing the app then
  /// loses them. Keep them on the device if a refusal ever shows up.
  List<Echeance> _aReprendre = const [];
  ListeDeCompte? _cible;
  Future<bool> _copie = Future.value(true);

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

  static Future<void> _oublierGoogleNatif() async {
    await _initialiserGoogle();
    await GoogleSignIn.instance.signOut();
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

  bool get _surIos => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// `select_account`: the user is asked which account, even when the browser already knows one.
  GoogleAuthProvider get _google => GoogleAuthProvider()..setCustomParameters({'prompt': 'select_account'});

  /// iOS: Firebase's web page loses its state in the browser ("missing initial state"), so Google's SDK signs in.
  Future<OAuthCredential?> _identifiantsIos() async {
    final jeton = await _jetonGoogle();
    return jeton == null ? null : GoogleAuthProvider.credential(idToken: jeton);
  }

  @override
  Future<ResultatGoogle> connecterAvecGoogle() => _traduireErreurs(() async {
    // Null between a sign-out and the new anonymous session.
    final utilisateur = _auth.currentUser;
    if (utilisateur == null) throw _echecGoogle('no-session');
    OAuthCredential? natif;
    if (_surIos) {
      natif = await _identifiantsIos();
      if (natif == null) return ResultatGoogle.annule;
    }
    try {
      if (natif != null) {
        await utilisateur.linkWithCredential(natif);
      } else {
        kIsWeb ? await utilisateur.linkWithPopup(_google) : await utilisateur.linkWithProvider(_google);
      }
      return ResultatGoogle.relie;
    } on FirebaseAuthException catch (e) {
      if (e.code != 'credential-already-in-use') rethrow;
      return await _fusionnerVers(natif ?? e.credential);
    }
  });

  /// The Google account already has its own Pli account: copy this device's deadlines there.
  ///
  /// Nothing is deleted first: until the copy is written, the deadlines must still exist somewhere.
  /// shortcut: the anonymous copy stays in Firestore, unreachable (the rules need its session, gone by then). Clean it
  /// up with the data deletion work (PRIV-002).
  Future<ResultatGoogle> _fusionnerVers(AuthCredential? identifiants) async {
    if (identifiants == null) throw _echecGoogle('no-credential');
    final List<Echeance> aReprendre;
    try {
      aReprendre = await _listeDe(uid).lister();
    } on FirebaseException catch (e) {
      // Still on the anonymous account: nothing changed, the user can try again.
      throw _echecGoogle(e.code);
    }
    await _auth.signInWithCredential(identifiants);
    if (aReprendre.isEmpty) return ResultatGoogle.connecte;
    _aReprendre = aReprendre;
    _cible = _listeDe(uid);
    relancerFusion();
    return ResultatGoogle.fusionEnCours;
  }

  @override
  void relancerFusion() => _copie = _copier();

  Future<bool> _copier() async {
    try {
      await _cible!.reprendre(_aReprendre);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> finFusion() => _copie;

  @override
  Future<ResultatGoogle> changerDeCompte() => _traduireErreurs(() async {
    if (_surIos) {
      await _oublierGoogleSansEchec(); // Otherwise Google's SDK may silently reuse the current account.
      final natif = await _identifiantsIos();
      if (natif == null) return ResultatGoogle.annule;
      await _auth.signInWithCredential(natif);
    } else {
      kIsWeb ? await _auth.signInWithPopup(_google) : await _auth.signInWithProvider(_google);
    }
    return ResultatGoogle.connecte;
  });

  @override
  Future<void> deconnecter() async {
    if (_surIos) await _oublierGoogleSansEchec();
    await _auth.signOut();
  }

  /// The Firebase session is what opens the list: changing it must not depend on Google's SDK.
  Future<void> _oublierGoogleSansEchec() async {
    try {
      await _oublierGoogle();
    } catch (_) {}
  }

  Future<ResultatGoogle> _traduireErreurs(Future<ResultatGoogle> Function() action) async {
    try {
      return await action();
    } on FirebaseAuthException catch (e) {
      return switch (e.code) {
        'popup-closed-by-user' ||
        'cancelled-popup-request' ||
        'web-context-canceled' ||
        'web-context-cancelled' => ResultatGoogle.annule,
        'popup-blocked' => throw const CompteImpossible(
          'Ton navigateur a bloqué la fenêtre Google : autorise les fenêtres pour ce site, puis réessaie.',
        ),
        _ => throw _echecGoogle(e.code),
      };
    }
  }
}
