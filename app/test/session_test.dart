import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pli/services/session.dart';

class _Identifiants extends Fake implements UserCredential {}

class _Utilisateur extends Fake implements User {
  _Utilisateur({this.erreur});

  final Object? erreur;
  var liaisons = 0;
  String? jetonRecu;

  @override
  bool get isAnonymous => true;

  @override
  String get uid => 'u1';

  @override
  String? get email => null;

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
  _Auth({this.currentUser, this.erreur});

  @override
  User? currentUser;
  final Object? erreur;
  var anonymes = 0;
  var connexions = 0;

  @override
  Future<UserCredential> signInAnonymously() async {
    anonymes++;
    currentUser = _Utilisateur();
    return _Identifiants();
  }

  @override
  Future<UserCredential> signInWithProvider(AuthProvider provider) async {
    connexions++;
    if (erreur != null) throw erreur!;
    return _Identifiants();
  }

  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    connexions++;
    if (erreur != null) throw erreur!;
    return _Identifiants();
  }
}

void main() {
  test('opening a session signs in anonymously only once', () async {
    final auth = _Auth();
    final session = Session(auth);
    await session.ouvrir();
    await session.ouvrir();
    expect(auth.anonymes, 1);
    expect(session.uid, 'u1');
    expect(session.estAnonyme, isTrue);
    expect(session.email, isNull);
    expect(await session.jeton(), 'jeton');
  });

  test('a list to keep is linked to Google, on the same account', () async {
    final utilisateur = _Utilisateur();
    final auth = _Auth(currentUser: utilisateur);
    expect(await Session(auth).garderAvecGoogle(listeVide: false), ResultatGoogle.relie);
    expect(utilisateur.liaisons, 1);
    expect(auth.connexions, 0);
  });

  test('an empty list simply opens the Google account', () async {
    final utilisateur = _Utilisateur();
    final auth = _Auth(currentUser: utilisateur);
    expect(await Session(auth).garderAvecGoogle(listeVide: true), ResultatGoogle.connecte);
    expect(auth.connexions, 1);
    expect(utilisateur.liaisons, 0);
  });

  for (final code in ['web-context-canceled', 'web-context-cancelled', 'popup-closed-by-user']) {
    test('closing the Google window ($code) is a cancel, not an error', () async {
      final auth = _Auth(
        currentUser: _Utilisateur(erreur: FirebaseAuthException(code: code)),
      );
      expect(await Session(auth).garderAvecGoogle(listeVide: false), ResultatGoogle.annule);
    });
  }

  for (final code in ['credential-already-in-use', 'email-already-in-use']) {
    test('two lists are never merged ($code)', () async {
      final auth = _Auth(
        currentUser: _Utilisateur(erreur: FirebaseAuthException(code: code)),
      );
      await expectLater(
        Session(auth).garderAvecGoogle(listeVide: false),
        throwsA(isA<CompteImpossible>().having((e) => e.message, 'message', contains('sa propre liste'))),
      );
    });
  }

  test('any other failure becomes a message the user can read', () async {
    final auth = _Auth(
      currentUser: _Utilisateur(),
      erreur: FirebaseAuthException(code: 'network-request-failed'),
    );
    await expectLater(
      Session(auth).garderAvecGoogle(listeVide: true),
      throwsA(isA<CompteImpossible>().having((e) => e.message, 'message', contains('Réessaie'))),
    );
  });

  group('on iOS, Google signs in through its own SDK', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    Future<String?> jeton() async => 'jeton-google';

    test('a list to keep is linked with Google\'s token, on the same account', () async {
      final utilisateur = _Utilisateur();
      final auth = _Auth(currentUser: utilisateur);
      expect(await Session(auth, jetonGoogle: jeton).garderAvecGoogle(listeVide: false), ResultatGoogle.relie);
      expect(utilisateur.liaisons, 1);
      expect(utilisateur.jetonRecu, 'jeton-google');
      expect(auth.connexions, 0);
    });

    test('an empty list simply opens the Google account', () async {
      final utilisateur = _Utilisateur();
      final auth = _Auth(currentUser: utilisateur);
      expect(await Session(auth, jetonGoogle: jeton).garderAvecGoogle(listeVide: true), ResultatGoogle.connecte);
      expect(auth.connexions, 1);
      expect(utilisateur.liaisons, 0);
    });

    test('closing the Google window is a cancel: the account does not change', () async {
      final utilisateur = _Utilisateur();
      final auth = _Auth(currentUser: utilisateur);
      final session = Session(auth, jetonGoogle: () async => null);
      expect(await session.garderAvecGoogle(listeVide: false), ResultatGoogle.annule);
      expect(utilisateur.liaisons, 0);
      expect(auth.connexions, 0);
    });

    test('two lists are never merged', () async {
      final auth = _Auth(
        currentUser: _Utilisateur(erreur: FirebaseAuthException(code: 'credential-already-in-use')),
      );
      await expectLater(
        Session(auth, jetonGoogle: jeton).garderAvecGoogle(listeVide: false),
        throwsA(isA<CompteImpossible>().having((e) => e.message, 'message', contains('sa propre liste'))),
      );
    });

    test('a Google failure reaches the user as a message', () async {
      final auth = _Auth(currentUser: _Utilisateur());
      await expectLater(
        Session(
          auth,
          jetonGoogle: () async => throw const CompteImpossible('Réessaie.'),
        ).garderAvecGoogle(listeVide: true),
        throwsA(isA<CompteImpossible>()),
      );
      expect(auth.connexions, 0);
    });
  });
}
