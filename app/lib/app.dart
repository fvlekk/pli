import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'ecrans/accueil.dart';
import 'services/depot_echeances.dart';
import 'services/lecteur_courrier.dart';
import 'theme.dart';

class PliApp extends StatelessWidget {
  const PliApp({super.key, required this.depot, required this.lecteur, this.maintenant = DateTime.now});

  final DepotEcheances depot;
  final LecteurCourrier lecteur;
  final DateTime Function() maintenant;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pli',
      debugShowCheckedModeBanner: false,
      theme: themePli(),
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // On a wide screen (web), keep a phone-width column instead of stretching the layout.
      builder: (context, enfant) => ColoredBox(
        color: Couleurs.fenetre,
        child: Center(
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: enfant),
        ),
      ),
      home: EcranAccueil(depot: depot, lecteur: lecteur, maintenant: maintenant),
    );
  }
}
