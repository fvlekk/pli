import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pli/modeles/echeance.dart';
import 'package:pli/services/depot_echeances.dart';
import 'package:pli/services/session.dart';

import 'faux.dart';

class _Identifiants extends Fake implements UserCredential {}

class _Utilisateur extends Fake implements User {
  _Utilisateur(this.uid, {this.erreur, this.isAnonymous = true, this.email, this.erreurConfirmation});

  @override
  final String uid;
  final Object? erreur;
  var liaisons = 0;
  String? jetonRecu;

  @override
  final bool isAnonymous;

  @override
  final String? email;

  /// What happened, in order: confirmations, then the deletion.
  final etapes = <String>[];
  final FirebaseAuthException? erreurConfirmation;
  FirebaseAuthException? erreurSuppression;
  _Auth? auth;

  @override
  Future<UserCredential> reauthenticateWithProvider(AuthProvider provider) async {
    etapes.add('confirmer');
    if (erreurConfirmation != null) throw erreurConfirmation!;
    return _Identifiants();
  }

  @override
  Future<UserCredential> reauthenticateWithCredential(AuthCredential credential) async {
    etapes.add('confirmer:${(credential as OAuthCredential).idToken}');
    if (erreurConfirmation != null) throw erreurConfirmation!;
    return _Identifiants();
  }

  @override
  Future<void> delete() async {
    etapes.add('supprimer');
    if (erreurSuppression != null) throw erreurSuppression!;
    auth?.currentUser = null; // Like Firebase: a deleted account is signed out.
  }

  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async => 'jeton';

  @override
  Future<UserCredential> linkWithProvider(AuthProvider provider) async {
    liaisons++;
    if (erreur != null) throw erreur!;
    return _Identifiants();
  }

  @override
  Future<UserCredential> linkWithCredential(AuthCredential credential) async {
    liaisons++;
    jetonRecu = (credential as OAuthCredential).idToken;
    if (erreur != null) throw erreur!;
    return _Identifiants();
  }
}

class _Auth extends Fake implements FirebaseAuth {
  _Auth({this.currentUser});

  @override
  User? currentUser;
  var anonymes = 0;
  var connexions = 0;
  var sorties = 0;
  String? jetonRecu;

  @override
  Future<UserCredential> signInAnonymously() async {
    anonymes++;
    currentUser = _Utilisateur('u1');
    return _Identifiants();
  }

  @override
  Future<UserCredential> signInWithProvider(AuthProvider provider) async {
    connexions++;
    currentUser = _Utilisateur('google');
    return _Identifiants();
  }

  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    jetonRecu = (credential as OAuthCredential).idToken;
    connexions++;
    currentUser = _Utilisateur('google');
    return _Identifiants();
  }

  @override
  Future<void> signOut() async {
    sorties++;
    currentUser = null;
  }
}

class _Liste implements ListeDeCompte {
  _Liste(this.uid, this.comptes);

  final String uid;
  final _Comptes comptes;

  @override
  Future<List<Echeance>> lister() async {
    if (comptes.erreurLecture != null) throw comptes.erreurLecture!;
    return comptes.listes[uid] ?? [];
  }

  @override
  Future<void> reprendre(List<Echeance> echeances) async {
    if (comptes.ecriture != null) await comptes.ecriture!();
    comptes.listes[uid] = [...?comptes.listes[uid], ...echeances];
  }

  @override
  Future<void> effacer() async {
    if (comptes.effacement != null) await comptes.effacement!();
    comptes.effaces.add(uid);
    comptes.listes.remove(uid);
  }
}

class _Comptes {
  final listes = <String, List<Echeance>>{};
  final effaces = <String>[];
  Object? erreurLecture;
  Future<void> Function()? ecriture;
  Future<void> Function()? effacement;

  ListeDeCompte de(String uid) => _Liste(uid, this);
}

void main() {
  late _Comptes comptes;
  setUp(() => comptes = _Comptes());

  Session session(_Auth auth, {Future<String?> Function()? jetonGoogle, Future<void> Function()? oublier}) => Session(
    auth,
    listeDe: comptes.de,
    jetonGoogle: jetonGoogle ?? () async => 'jeton-google',
    oublierGoogle: oublier ?? () async {},
  );

  /// Google refuses the link: this account already exists.
  _Auth authEnConflit() => _Auth(
    currentUser: _Utilisateur(
      'anonyme',
      erreur: FirebaseAuthException(
        code: 'credential-already-in-use',
        credential: GoogleAuthProvider.credential(idToken: 'jeton-du-conflit'),
      ),
    ),
  );

  test('opening a session signs in anonymously only once', () async {
    final auth = _Auth();
    final s = session(auth);
    await s.ouvrir();
    await s.ouvrir();
    expect(auth.anonymes, 1);
    expect(s.uid, 'u1');
    expect(s.estAnonyme, isTrue);
    expect(s.email, isNull);
    expect(await s.jeton(), 'jeton');
  });

  test('a new Google account is linked: same account, same list', () async {
    final utilisateur = _Utilisateur('anonyme');
    final auth = _Auth(currentUser: utilisateur);
    expect(await session(auth).connecterAvecGoogle(), ResultatGoogle.relie);
    expect(utilisateur.liaisons, 1);
    expect(auth.connexions, 0);
  });

  test("an account with its own list: this device's deadlines join it, the others stay", () async {
    comptes.listes['anonyme'] = [echeance(id: 'a', titre: 'Ici')];
    comptes.listes['google'] = [echeance(id: 'b', titre: 'Déjà là')];
    final auth = authEnConflit();
    final s = session(auth);
    expect(await s.connecterAvecGoogle(), ResultatGoogle.fusionEnCours);
    expect(await s.finFusion(), isTrue);
    expect(auth.jetonRecu, 'jeton-du-conflit');
    expect(auth.currentUser!.uid, 'google');
    expect(comptes.listes['google']!.map((e) => e.titre), ['Déjà là', 'Ici']);
    expect(comptes.listes['anonyme'], hasLength(1), reason: 'nothing is deleted on the way');
  });

  test('nothing to bring: the existing list simply opens', () async {
    final auth = authEnConflit();
    expect(await session(auth).connecterAvecGoogle(), ResultatGoogle.connecte);
    expect(auth.currentUser!.uid, 'google');
  });

  test('if the list cannot be read, the account does not change', () async {
    comptes.erreurLecture = FirebaseException(plugin: 'firestore', code: 'unavailable');
    final auth = authEnConflit();
    await expectLater(session(auth).connecterAvecGoogle(), throwsA(isA<CompteImpossible>()));
    expect(auth.connexions, 0);
    expect(auth.currentUser!.uid, 'anonyme');
  });

  test('a refused copy is reported, then the same deadlines can be sent again', () async {
    comptes.listes['anonyme'] = [echeance(titre: 'Ici')];
    comptes.ecriture = () async => throw FirebaseException(plugin: 'firestore', code: 'permission-denied');
    final auth = authEnConflit();
    final s = session(auth);
    expect(await s.connecterAvecGoogle(), ResultatGoogle.fusionEnCours);
    expect(await s.finFusion(), isFalse);
    expect(auth.currentUser!.uid, 'google');

    comptes.ecriture = null;
    s.relancerFusion();
    expect(await s.finFusion(), isTrue);
    expect(comptes.listes['google']!.single.titre, 'Ici');
  });

  test('without network the copy waits, and is never reported as finished before the server has it', () async {
    comptes.listes['anonyme'] = [echeance()];
    final serveur = Completer<void>();
    comptes.ecriture = () => serveur.future;
    final s = session(authEnConflit());
    expect(await s.connecterAvecGoogle(), ResultatGoogle.fusionEnCours, reason: 'the user is not held back');
    var finie = false;
    unawaited(s.finFusion().then((_) => finie = true));
    await pumpEventQueue();
    expect(finie, isFalse);
    serveur.complete();
    expect(await s.finFusion(), isTrue);
  });

  test('without a session (just after a sign-out), a message instead of a crash', () async {
    await expectLater(session(_Auth()).connecterAvecGoogle(), throwsA(isA<CompteImpossible>()));
  });

  test('a conflict without a credential is a message, and the account does not change', () async {
    final auth = _Auth(
      currentUser: _Utilisateur('anonyme', erreur: FirebaseAuthException(code: 'credential-already-in-use')),
    );
    await expectLater(session(auth).connecterAvecGoogle(), throwsA(isA<CompteImpossible>()));
    expect(auth.connexions, 0);
  });

  for (final code in ['web-context-canceled', 'web-context-cancelled', 'popup-closed-by-user']) {
    test('closing the Google window ($code) is a cancel, not an error', () async {
      final auth = _Auth(
        currentUser: _Utilisateur('anonyme', erreur: FirebaseAuthException(code: code)),
      );
      expect(await session(auth).connecterAvecGoogle(), ResultatGoogle.annule);
    });
  }

  test('any other failure becomes a message the user can read', () async {
    final auth = _Auth(
      currentUser: _Utilisateur('anonyme', erreur: FirebaseAuthException(code: 'network-request-failed')),
    );
    await expectLater(
      session(auth).connecterAvecGoogle(),
      throwsA(isA<CompteImpossible>().having((e) => e.message, 'message', contains('Réessaie'))),
    );
  });

  test('changing account opens the other one, without copying anything', () async {
    comptes.listes['anonyme'] = [echeance()];
    final auth = _Auth(currentUser: _Utilisateur('anonyme'));
    expect(await session(auth).changerDeCompte(), ResultatGoogle.connecte);
    expect(auth.currentUser!.uid, 'google');
    expect(comptes.listes['google'], isNull);
  });

  test('signing out ends the Firebase session', () async {
    final auth = _Auth(currentUser: _Utilisateur('google'));
    await session(auth).deconnecter();
    expect(auth.sorties, 1);
    expect(auth.currentUser, isNull);
  });

  group('deleting my data', () {
    /// A signed-in user whose deletion reaches [auth] like Firebase does.
    _Auth authAvec(_Utilisateur utilisateur) {
      final auth = _Auth(currentUser: utilisateur);
      utilisateur.auth = auth;
      return auth;
    }

    test('without Google: the deadlines, then the account; the other lists stay', () async {
      comptes.listes['anonyme'] = [echeance()];
      comptes.listes['autre'] = [echeance()];
      final utilisateur = _Utilisateur('anonyme');
      final auth = authAvec(utilisateur);
      expect(await session(auth).supprimerMesDonnees(), isTrue);
      expect(comptes.effaces, ['anonyme']);
      expect(comptes.listes.keys, ['autre']);
      expect(utilisateur.etapes, ['supprimer']);
      expect(auth.currentUser, isNull);
    });

    test('a Google account confirms who it is before anything is erased', () async {
      comptes.listes['google'] = [echeance()];
      final utilisateur = _Utilisateur('google', isAnonymous: false, email: 'a@exemple.fr');
      final auth = authAvec(utilisateur);
      comptes.effacement = () async => expect(utilisateur.etapes, ['confirmer']);
      expect(await session(auth).supprimerMesDonnees(), isTrue);
      expect(utilisateur.etapes, ['confirmer', 'supprimer']);
      expect(comptes.effaces, ['google']);
    });

    for (final code in ['popup-closed-by-user', 'web-context-canceled']) {
      test('closing the Google window ($code) erases nothing', () async {
        comptes.listes['google'] = [echeance()];
        final utilisateur = _Utilisateur(
          'google',
          isAnonymous: false,
          erreurConfirmation: FirebaseAuthException(code: code),
        );
        expect(await session(authAvec(utilisateur)).supprimerMesDonnees(), isFalse);
        expect(comptes.effaces, isEmpty);
        expect(utilisateur.etapes, ['confirmer']);
      });
    }

    test('another Google account than the list\'s own is refused, and nothing is erased', () async {
      final utilisateur = _Utilisateur(
        'google',
        isAnonymous: false,
        email: 'a@exemple.fr',
        erreurConfirmation: FirebaseAuthException(code: 'user-mismatch'),
      );
      await expectLater(
        session(authAvec(utilisateur)).supprimerMesDonnees(),
        throwsA(isA<CompteImpossible>().having((e) => e.message, 'message', contains('a@exemple.fr'))),
      );
      expect(comptes.effaces, isEmpty);
    });

    test('a blocked Google window says how to allow it', () async {
      final utilisateur = _Utilisateur(
        'google',
        isAnonymous: false,
        erreurConfirmation: FirebaseAuthException(code: 'popup-blocked'),
      );
      await expectLater(
        session(authAvec(utilisateur)).supprimerMesDonnees(),
        throwsA(isA<CompteImpossible>().having((e) => e.message, 'message', contains('autorise les fenêtres'))),
      );
    });

    test('offline, the account is kept: its deadlines are not all erased', () async {
      comptes.effacement = () async => throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
      final utilisateur = _Utilisateur('anonyme');
      final auth = authAvec(utilisateur);
      await expectLater(
        session(auth).supprimerMesDonnees(),
        throwsA(isA<CompteImpossible>().having((e) => e.message, 'message', contains('connexion'))),
      );
      expect(utilisateur.etapes, isEmpty);
      expect(auth.currentUser, same(utilisateur));
    });

    testWidgets('a server that never answers is given up after 20 s, and the account is kept', (tester) async {
      comptes.effacement = () => Completer<void>().future;
      final utilisateur = _Utilisateur('anonyme');
      Object? erreur;
      unawaited(
        session(authAvec(utilisateur)).supprimerMesDonnees().then<void>((_) {}, onError: (Object e) => erreur = e),
      );
      await tester.pump(const Duration(seconds: 19));
      expect(erreur, isNull);
      await tester.pump(const Duration(seconds: 2));
      expect(erreur, isA<CompteImpossible>());
      expect(utilisateur.etapes, isEmpty);
    });

    test('without Google, an old session that cannot delete itself is signed out, its list already empty', () async {
      comptes.listes['anonyme'] = [echeance()];
      final utilisateur = _Utilisateur('anonyme')
        ..erreurSuppression = FirebaseAuthException(code: 'requires-recent-login');
      final auth = authAvec(utilisateur);
      expect(await session(auth).supprimerMesDonnees(), isTrue);
      expect(comptes.effaces, ['anonyme']);
      expect(auth.sorties, 1);
      expect(auth.currentUser, isNull);
    });

    test('a Google account that could not be deleted says its deadlines are gone, and stays open', () async {
      final utilisateur = _Utilisateur('google', isAnonymous: false)
        ..erreurSuppression = FirebaseAuthException(code: 'network-request-failed');
      final auth = authAvec(utilisateur);
      await expectLater(
        session(auth).supprimerMesDonnees(),
        throwsA(isA<CompteImpossible>().having((e) => e.message, 'message', contains('pas ton compte'))),
      );
      expect(comptes.effaces, ['google']);
      expect(auth.sorties, 0);
    });

    test('a merge copy still on its way finishes before the erase, so nothing lands in a deleted account', () async {
      comptes.listes['anonyme'] = [echeance()];
      final copie = Completer<void>();
      comptes.ecriture = () => copie.future;
      final auth = authEnConflit();
      final s = session(auth);
      expect(await s.connecterAvecGoogle(), ResultatGoogle.fusionEnCours);
      final google = _Utilisateur('google', isAnonymous: false)..auth = auth;
      auth.currentUser = google;
      final suppression = s.supprimerMesDonnees();
      await Future<void>.delayed(Duration.zero);
      expect(comptes.effaces, isEmpty, reason: 'waits for the copy');
      copie.complete();
      expect(await suppression, isTrue);
      expect(comptes.effaces, ['google']);
      expect(comptes.listes['google'], isNull, reason: 'the copied deadlines are erased too');
    });

    test('without a session, a message instead of a crash', () async {
      await expectLater(session(_Auth()).supprimerMesDonnees(), throwsA(isA<CompteImpossible>()));
    });
  });

  group('on iOS, Google signs in through its own SDK', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test("linking uses Google's token", () async {
      final utilisateur = _Utilisateur('anonyme');
      final auth = _Auth(currentUser: utilisateur);
      expect(await session(auth).connecterAvecGoogle(), ResultatGoogle.relie);
      expect(utilisateur.jetonRecu, 'jeton-google');
      expect(auth.connexions, 0);
    });

    test("a merge signs in with Google's token", () async {
      comptes.listes['anonyme'] = [echeance()];
      final auth = authEnConflit();
      final s = session(auth);
      expect(await s.connecterAvecGoogle(), ResultatGoogle.fusionEnCours);
      expect(await s.finFusion(), isTrue);
      expect(auth.jetonRecu, 'jeton-google');
      expect(comptes.listes['google'], hasLength(1));
    });

    test('closing the Google window is a cancel: the account does not change', () async {
      final utilisateur = _Utilisateur('anonyme');
      final auth = _Auth(currentUser: utilisateur);
      final s = session(auth, jetonGoogle: () async => null);
      expect(await s.connecterAvecGoogle(), ResultatGoogle.annule);
      expect(await s.changerDeCompte(), ResultatGoogle.annule);
      expect(utilisateur.liaisons, 0);
      expect(auth.connexions, 0);
    });

    test('changing account forgets the current Google account first, then signs in with the token', () async {
      var oublis = 0;
      final auth = _Auth(currentUser: _Utilisateur('anonyme'));
      expect(await session(auth, oublier: () async => oublis++).changerDeCompte(), ResultatGoogle.connecte);
      expect(oublis, 1);
      expect(auth.jetonRecu, 'jeton-google');
    });

    test("signing out survives a failure of Google's SDK", () async {
      var oublis = 0;
      final auth = _Auth(currentUser: _Utilisateur('google'));
      await session(
        auth,
        oublier: () async {
          oublis++;
          throw StateError('sdk');
        },
      ).deconnecter();
      expect(oublis, 1);
      expect(auth.sorties, 1);
    });
    test("deleting a Google account confirms it with Google's token, then forgets Google's session", () async {
      var oublis = 0;
      final utilisateur = _Utilisateur('google', isAnonymous: false);
      final auth = _Auth(currentUser: utilisateur);
      utilisateur.auth = auth;
      expect(await session(auth, oublier: () async => oublis++).supprimerMesDonnees(), isTrue);
      expect(utilisateur.etapes, ['confirmer:jeton-google', 'supprimer']);
      expect(oublis, 1);
    });

    test('closing the Google window while deleting erases nothing', () async {
      final utilisateur = _Utilisateur('google', isAnonymous: false);
      final auth = _Auth(currentUser: utilisateur);
      expect(await session(auth, jetonGoogle: () async => null).supprimerMesDonnees(), isFalse);
      expect(utilisateur.etapes, isEmpty);
      expect(comptes.effaces, isEmpty);
    });
  });
}
