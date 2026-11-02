import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'config.dart';
import 'demo/depot_memoire.dart';
import 'demo/lecteur_demo.dart';
import 'ecrans/demarrage.dart';
import 'services/depot_echeances.dart';
import 'services/lecteur_courrier.dart';
import 'services/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr');
  if (Config.demo) {
    runApp(PliApp(depot: DepotMemoire.demo(DateTime.now()), lecteur: LecteurDemo()));
    return;
  }

  await demarrer();
}

/// Web only: on Android and iOS, App Check would need Play Integrity and DeviceCheck, which are not set up.
final _appCheck = kIsWeb && Config.cleRecaptcha.isNotEmpty;
var _firebasePret = false;

/// Firebase and the anonymous session must be up before the app can show anything. When they fail (offline, an
/// ad blocker), show a retry screen instead of a blank page.
Future<void> demarrer() async {
  try {
    runApp(await _appConnectee());
  } catch (_) {
    runApp(EcranDemarrageImpossible(onReessayer: demarrer));
  }
}

Future<Widget> _appConnectee() async {
  if (!_firebasePret) {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: Config.optionsFirebase);
    if (Config.emulateurs) {
      await FirebaseAuth.instance.useAuthEmulator(Config.hoteEmulateurs, 9099);
      FirebaseFirestore.instance.useFirestoreEmulator(Config.hoteEmulateurs, 8085);
    }
    // Firestore and Auth then attach App Check tokens by themselves; the backend gets one per request below.
    if (_appCheck) {
      await FirebaseAppCheck.instance.activate(providerWeb: ReCaptchaEnterpriseProvider(Config.cleRecaptcha));
    }
    _firebasePret = true;
  }
  final session = Session(FirebaseAuth.instance);
  await session.ouvrir().timeout(const Duration(seconds: 20));

  return PliApp(
    depot: DepotFirestore(FirebaseFirestore.instance, session.uid),
    lecteur: LecteurHttp(
      urlApi: Config.urlApi,
      jeton: session.jeton,
      jetonApp: _appCheck ? FirebaseAppCheck.instance.getToken : null,
    ),
  );
}
