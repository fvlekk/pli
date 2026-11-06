import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'ecrans/accueil.dart';
import 'services/depot_echeances.dart';
import 'services/lecteur_courrier.dart';
import 'services/session.dart';
import 'theme.dart';

class PliApp extends StatelessWidget {
  const PliApp({
    super.key,
    required this.depot,
    required this.lecteur,
    this.compte,
    this.onCompteChange,
    this.maintenant = DateTime.now,
  });

  final DepotEcheances depot;
  final LecteurCourrier lecteur;

  /// Null in the demo: no account to keep.
  final Compte? compte;

  /// Called when the user opened another account's list: the app restarts on it.
  final VoidCallback? onCompteChange;
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
      // A number pad has no key to close it: a tap anywhere that is not a control closes the keyboard.
      builder: (context, enfant) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        excludeFromSemantics: true,
        onTap: () {
          // No field focused: the focus is on the open sheet's scope, and it must stay there for Esc to close it.
          final focus = FocusManager.instance.primaryFocus;
          if (focus is! FocusScopeNode) focus?.unfocus();
        },
        child: ColoredBox(
          color: Couleurs.fond,
          child: Center(
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: enfant),
          ),
        ),
      ),
      home: EcranAccueil(
        depot: depot,
        lecteur: lecteur,
        compte: compte,
        onCompteChange: onCompteChange,
        maintenant: maintenant,
      ),
    );
  }
}
