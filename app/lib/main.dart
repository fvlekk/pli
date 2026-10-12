import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'config.dart';
import 'services/depot_echeances.dart';
import 'services/lecteur_courrier.dart';
import 'services/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr');
  await Firebase.initializeApp(options: Config.optionsFirebase);
  if (Config.emulateurs) {
    await FirebaseAuth.instance.useAuthEmulator(Config.hoteEmulateurs, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(Config.hoteEmulateurs, 8085);
  }
  final session = Session(FirebaseAuth.instance);
  await session.ouvrir();

  runApp(
    PliApp(
      depot: DepotFirestore(FirebaseFirestore.instance, session.uid),
      lecteur: LecteurHttp(urlApi: Config.urlApi, jeton: session.jeton),
    ),
  );
}
