import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:pli/services/depot_echeances.dart';
import 'package:pli/services/session.dart';

class _Identifiants extends Fake implements UserCredential {}

class _Utilisateur extends Fake implements User {
  String? jetonRecu;

  @override
  Future<UserCredential> linkWithCredential(AuthCredential credential) async {
    jetonRecu = (credential as OAuthCredential).idToken;
    return _Identifiants();
  }
}

class _Auth extends Fake implements FirebaseAuth {
  @override
  final _Utilisateur currentUser = _Utilisateur();
}

class _SansListe extends Fake implements ListeDeCompte {}

class _Plateforme extends GoogleSignInPlatform {
  var initialisations = 0;
  Object? erreurInit;
  Object? erreurConnexion;
  String? idToken = 'jeton-google';

  @override
  Future<void> init(InitParameters params) async {
    initialisations++;
    if (erreurInit != null) throw erreurInit!;
  }

  @override
  Future<AuthenticationResults> authenticate(AuthenticateParameters params) async {
    if (erreurConnexion != null) throw erreurConnexion!;
    return AuthenticationResults(
      user: const GoogleSignInUserData(email: 'test@example.test', id: '1'),
      authenticationTokens: AuthenticationTokenData(idToken: idToken),
    );
  }

  @override
  // ignore: unnecessary_overrides, the platform interface's other methods are never called here
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Plateforme plateforme;
  late _Auth auth;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    plateforme = _Plateforme();
    GoogleSignInPlatform.instance = plateforme;
    auth = _Auth();
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  Future<ResultatGoogle> garder() => Session(auth, listeDe: (_) => _SansListe()).connecterAvecGoogle();

  final messageLisible = throwsA(isA<CompteImpossible>().having((e) => e.message, 'message', contains('Réessaie')));

  // First on purpose: the plugin's initialization is kept for the whole process.
  test('a failed initialization is a readable message, and retrying runs it again', () async {
    plateforme.erreurInit = PlatformException(code: 'channel-error');
    await expectLater(garder(), messageLisible);
    plateforme.erreurInit = null;
    expect(await garder(), ResultatGoogle.relie);
    expect(plateforme.initialisations, 2);
  });

  test('once it succeeded, the initialization never runs again', () async {
    expect(await garder(), ResultatGoogle.relie);
    expect(plateforme.initialisations, 0);
  });

  test("Google's token reaches Firebase", () async {
    expect(await garder(), ResultatGoogle.relie);
    expect(auth.currentUser.jetonRecu, 'jeton-google');
  });

  test('closing the Google window is a cancel', () async {
    plateforme.erreurConnexion = const GoogleSignInException(code: GoogleSignInExceptionCode.canceled);
    expect(await garder(), ResultatGoogle.annule);
    expect(auth.currentUser.jetonRecu, isNull);
  });

  test('a Google failure is a readable message', () async {
    plateforme.erreurConnexion = const GoogleSignInException(code: GoogleSignInExceptionCode.uiUnavailable);
    await expectLater(garder(), messageLisible);
  });

  test('an error from outside the plugin\'s mapping is a readable message, never silent', () async {
    plateforme.erreurConnexion = PlatformException(code: 'com.google.HTTPStatus: 500');
    await expectLater(garder(), messageLisible);
  });

  test('a sign-in without a token is a readable message, not a cancel', () async {
    plateforme.idToken = null;
    await expectLater(garder(), messageLisible);
    expect(auth.currentUser.jetonRecu, isNull);
  });
}
