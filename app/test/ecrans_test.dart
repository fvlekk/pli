import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pli/app.dart';
import 'package:pli/ecrans/ajout.dart';
import 'package:pli/ecrans/feuille_compte.dart';
import 'package:pli/ecrans/demarrage.dart';
import 'package:pli/ecrans/verification.dart';
import 'package:pli/modeles/echeance.dart';
import 'package:pli/modeles/lecture.dart';
import 'package:pli/services/depot_echeances.dart';
import 'package:pli/services/lecteur_courrier.dart';
import 'package:pli/services/session.dart';
import 'package:pli/theme.dart';

import 'faux.dart';

Widget appli(FauxDepot depot, {FauxLecteur? lecteur}) =>
    PliApp(depot: depot, lecteur: lecteur ?? FauxLecteur(), maintenant: () => aujourdhui);

Widget verification(FauxDepot depot, {required dynamic l}) => MaterialApp(
  theme: themePli(),
  home: EcranVerification(lecture: l, depot: depot, maintenant: () => aujourdhui),
);

/// The samples sit at the bottom of the add screen, built only once close to the screen.
/// The sheet's list only builds what fits: brings an option into view.
Future<void> montrerDansLaFeuille(WidgetTester tester, Finder cible) async {
  final liste = find.descendant(of: find.byType(FeuilleAjout), matching: find.byType(Scrollable)).first;
  await tester.scrollUntilVisible(cible, 100, scrollable: liste);
  await tester.pumpAndSettle();
}

/// From the open sheet: pastes a letter and starts reading it.
Future<void> lireUnTexte(WidgetTester tester) async {
  await montrerDansLaFeuille(tester, find.text('Coller le texte'));
  await tester.tap(find.text('Coller le texte'));
  await tester.pumpAndSettle();
  await montrerDansLaFeuille(tester, find.text('Lire ce texte'));
  await tester.enterText(find.widgetWithText(TextField, 'Texte du courrier'), 'Un courrier fictif.');
  await tester.pumpAndSettle();
  await tester.tap(find.text('Lire ce texte'));
}

class _CompteCasse extends FauxCompte {
  @override
  Future<ResultatGoogle> connecterAvecGoogle() async => throw StateError('panne');
}

class _CompteLent extends FauxCompte {
  _CompteLent(this.sortie) : super(estAnonyme: false, email: 'camille@exemple.fr');

  final Future<void> Function() sortie;

  @override
  Future<void> deconnecter() => sortie();
}

void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  testWidgets('empty home invites to add the first letter', (tester) async {
    await tester.pumpWidget(appli(FauxDepot()));
    await tester.pumpAndSettle();
    expect(find.text('Aucun courrier en attente'), findsOneWidget);
    expect(find.text('Rien d\'urgent cette semaine.'), findsNothing, reason: 'the empty state already says it');
    expect(find.text('Ajouter un courrier'), findsOneWidget);
  });

  testWidgets('deadlines are grouped by horizon, late ones first', (tester) async {
    final depot = FauxDepot([
      echeance(id: 'a', titre: 'Payer l\'amende', dateLimite: DateTime(2026, 10, 18)),
      echeance(id: 'b', titre: 'Déclarer le CA', dateLimite: DateTime(2026, 10, 31), montant: null),
      echeance(id: 'c', titre: 'Faire le DSE', dateLimite: DateTime(2027, 5, 15), montant: null),
      echeance(id: 'd', titre: 'Payer le loyer', dateLimite: DateTime(2026, 10, 10)),
      echeance(id: 'e', titre: 'Envoyer l\'attestation', dateLimite: DateTime(2026, 10, 1), fait: true),
    ]);
    await tester.binding.setSurfaceSize(const Size(420, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(appli(depot));
    await tester.pumpAndSettle();

    final titres = ['En retard', 'Cette semaine', 'Ce mois-ci', 'Plus tard'];
    // .first: the section title comes before the cards, whose countdown pill can also say « En retard ».
    final positions = [for (final t in titres) tester.getTopLeft(find.text(t).first).dy];
    expect(positions, orderedEquals([...positions]..sort()), reason: 'panels in time order');
    expect(find.text('Une démarche est en retard.'), findsOneWidget);
    expect(find.text('Fait (1)'), findsOneWidget);
    expect(find.text('Envoyer l\'attestation'), findsNothing, reason: 'done items stay folded');
    expect(find.text('90 €'), findsWidgets);
    expect(find.text('À FAIRE EN PREMIER'), findsOneWidget, reason: 'only the most pressing card is highlighted');
    expect(
      tester.getTopLeft(find.text('À FAIRE EN PREMIER')).dy,
      lessThan(tester.getTopLeft(find.text('Payer l\'amende')).dy),
      reason: 'the highlighted card is the late one, above this week\'s',
    );
  });

  testWidgets('a letter is read, checked, then saved', (tester) async {
    final depot = FauxDepot();
    final lecteur = FauxLecteur(reponse: lecture());
    await tester.pumpWidget(appli(depot, lecteur: lecteur));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ajouter un courrier'));
    await tester.pumpAndSettle();
    await lireUnTexte(tester);
    await tester.pumpAndSettle();

    expect(lecteur.recus.single, isA<CourrierTexte>());
    expect(find.text('Vérifie avant d\'enregistrer'), findsOneWidget);
    await tester.tap(find.text('Enregistrer l\'échéance'));
    await tester.pumpAndSettle();

    expect(depot.ajoutees.single.titre, 'Payer l\'amende');
    expect(depot.ajoutees.single.dateLimite, DateTime(2026, 10, 18));
    expect(find.text('Échéance enregistrée'), findsOneWidget);
    expect(
      find.text('Payer l\'amende · avant\u00a0le\u00a018\u00a0oct.'),
      findsOneWidget,
      reason: 'says what was kept, and for when',
    );
    expect(find.text('Payer l\'amende'), findsOneWidget);
  });

  testWidgets('a reading error is explained on the add screen', (tester) async {
    final lecteur = FauxLecteur(erreur: const LectureImpossible('Pas de connexion au service de lecture.'));
    await tester.pumpWidget(appli(FauxDepot(), lecteur: lecteur));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter un courrier'));
    await tester.pumpAndSettle();
    await lireUnTexte(tester);
    await tester.pumpAndSettle();
    expect(find.text('Pas de connexion au service de lecture.'), findsOneWidget);
  });

  testWidgets('uncertain readings are flagged and keep the flag', (tester) async {
    final depot = FauxDepot();
    await tester.pumpWidget(verification(depot, l: lecture(aVerifier: true, raison: 'deux délais possibles')));
    await tester.pumpAndSettle();
    expect(find.text('À vérifier'), findsOneWidget);
    expect(find.text('Deux délais possibles.'), findsOneWidget);
    await tester.tap(find.text('Enregistrer l\'échéance'));
    await tester.pumpAndSettle();
    expect(depot.ajoutees.single.aVerifier, isTrue);
  });

  testWidgets('without a date, saving waits for the user to pick one', (tester) async {
    await tester.pumpWidget(verification(FauxDepot(), l: lecture(sansDate: true)));
    await tester.pumpAndSettle();
    final bouton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Choisis une date pour enregistrer'));
    expect(bouton.onPressed, isNull);
  });

  testWidgets('an information letter says there is nothing to do', (tester) async {
    final depot = FauxDepot();
    await tester.pumpWidget(verification(depot, l: lecture(action: 'aucune', sansDate: true, montant: null)));
    await tester.pumpAndSettle();
    expect(find.text('Rien à faire avec ce courrier'), findsOneWidget);
    expect(find.text('Créer un rappel quand même'), findsOneWidget);
    expect(depot.ajoutees, isEmpty);
  });

  testWidgets('an invalid amount is refused with an example', (tester) async {
    final depot = FauxDepot();
    await tester.pumpWidget(verification(depot, l: lecture()));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Montant (facultatif)'), '90 euros et des poussières');
    await tester.tap(find.text('Enregistrer l\'échéance'));
    await tester.pumpAndSettle();
    expect(find.text('Écris un montant comme 90 ou 87,42'), findsOneWidget);
    expect(depot.ajoutees, isEmpty);
  });

  testWidgets('texts longer than the Firestore rules allow are cut before saving', (tester) async {
    final depot = FauxDepot();
    await tester.pumpWidget(verification(depot, l: lecture(titre: 'Payer ${'x' * 300}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer l\'échéance'));
    await tester.pumpAndSettle();
    expect(depot.ajoutees.single.titre.length, 120);
  });

  testWidgets('a date read far in the past still opens the date picker', (tester) async {
    await tester.pumpWidget(verification(FauxDepot(), l: lecture(dateLimite: DateTime(2019, 3, 1))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('vendredi 1 mars 2019'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  testWidgets('a slow reading says the service is waking up, then goes on', (tester) async {
    // Tall enough that the status line at the top stays built while the button at the bottom is tapped.
    await tester.binding.setSurfaceSize(const Size(420, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final lecteur = _LecteurLent();
    await tester.pumpWidget(PliApp(depot: FauxDepot(), lecteur: lecteur, maintenant: () => aujourdhui));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter un courrier'));
    await tester.pumpAndSettle();
    await lireUnTexte(tester);
    await tester.pump();
    expect(find.text('Je lis ton courrier…'), findsOneWidget);
    await tester.pump(attenteLente + const Duration(seconds: 1));
    expect(find.text('Le service se réveille, ça peut prendre une minute…'), findsOneWidget);
    lecteur.attendue.complete(lecture());
    await tester.pumpAndSettle();
    expect(find.text('Vérifie avant d\'enregistrer'), findsOneWidget);
  });

  testWidgets('a reason that already ends with a period gets no second one', (tester) async {
    final l = lecture(aVerifier: true, raison: 'le montant de 135 € a donc été retenu.');
    await tester.pumpWidget(verification(FauxDepot(), l: l));
    await tester.pumpAndSettle();
    expect(find.text('Le montant de 135 € a donc été retenu.'), findsOneWidget);
  });

  testWidgets('tapping a deadline card opens its details', (tester) async {
    await tester.pumpWidget(appli(FauxDepot([echeance()])));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Payer l\'amende'));
    await tester.pumpAndSettle();
    expect(find.text('C\'est fait'), findsOneWidget);
  });

  testWidgets('when the app cannot start, it says so and retries', (tester) async {
    var essais = 0;
    await tester.pumpWidget(EcranDemarrageImpossible(onReessayer: () async => essais++));
    expect(find.text('Pli n\'arrive pas à démarrer'), findsOneWidget);
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(essais, 1);
    expect(find.text('Réessayer'), findsOneWidget, reason: 'the button comes back if the retry failed too');
  });

  testWidgets('an unexpected failure while reading is shown, never swallowed', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(PliApp(depot: FauxDepot(), lecteur: _LecteurEnPanne(), maintenant: () => aujourdhui));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter un courrier'));
    await tester.pumpAndSettle();
    await lireUnTexte(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('La lecture a échoué'), findsOneWidget);
    expect(find.text('Je lis ton courrier…'), findsNothing, reason: 'the screen is usable again');
  });

  group('Google account', () {
    Future<void> accueil(WidgetTester tester, FauxDepot depot, Compte? compte, {VoidCallback? onCompteChange}) async {
      await tester.binding.setSurfaceSize(const Size(420, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        PliApp(
          depot: depot,
          lecteur: FauxLecteur(),
          compte: compte,
          onCompteChange: onCompteChange,
          maintenant: () => aujourdhui,
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> ouvrirCompte(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Mon compte'));
      await tester.pumpAndSettle();
    }

    Future<void> continuerAvecGoogle(WidgetTester tester) async {
      await ouvrirCompte(tester);
      await tester.tap(find.text('Continuer avec Google'));
      await tester.pumpAndSettle();
    }

    testWidgets('no card on the list: the account lives behind its button', (tester) async {
      await accueil(tester, FauxDepot([echeance()]), FauxCompte());
      expect(find.textContaining('Google'), findsNothing);
      await ouvrirCompte(tester);
      expect(find.text('Continuer avec Google'), findsOneWidget);
      expect(find.text('Se déconnecter'), findsNothing, reason: 'leaving an anonymous account would lose its list');
    });

    testWidgets('an anonymous list stays with Google, same account', (tester) async {
      final compte = FauxCompte();
      await accueil(tester, FauxDepot([echeance()]), compte);
      await continuerAvecGoogle(tester);
      expect(compte.appels, ['connecter']);
      expect(find.text('Compte Google connecté'), findsOneWidget);
      expect(find.text('Continuer avec Google'), findsNothing);
    });

    testWidgets('joining an existing list restarts on it, and says « added » once the server has them', (tester) async {
      var redemarrages = 0;
      final compte = FauxCompte(resultat: ResultatGoogle.fusionEnCours);
      await accueil(tester, FauxDepot([echeance()]), compte, onCompteChange: () => redemarrages++);
      await continuerAvecGoogle(tester);
      expect(redemarrages, 1);
      expect(find.text('Échéances ajoutées à ta liste'), findsOneWidget);
    });

    testWidgets('a refused copy blocks the screen until it is retried or given up', (tester) async {
      final compte = FauxCompte(resultat: ResultatGoogle.fusionEnCours)
        ..fusions.clear()
        ..fusions.addAll([false, true]);
      await accueil(tester, FauxDepot([echeance()]), compte);
      await continuerAvecGoogle(tester);
      expect(find.text('Échéances non ajoutées'), findsOneWidget);
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(compte.appels, ['connecter', 'relancer']);
      expect(find.text('Échéances non ajoutées'), findsNothing);
      expect(find.text('Échéances ajoutées à ta liste'), findsOneWidget);
    });

    testWidgets('giving up on a refused copy never announces it as added', (tester) async {
      final compte = FauxCompte(resultat: ResultatGoogle.fusionEnCours)
        ..fusions.clear()
        ..fusions.add(false);
      await accueil(tester, FauxDepot([echeance()]), compte);
      await continuerAvecGoogle(tester);
      await tester.tap(find.text('Abandonner'));
      await tester.pumpAndSettle();
      expect(find.text('Échéances ajoutées à ta liste'), findsNothing);
    });

    testWidgets('an unexpected failure is explained, the sheet does not stay stuck', (tester) async {
      await accueil(tester, FauxDepot([echeance()]), _CompteCasse());
      await continuerAvecGoogle(tester);
      expect(find.text('Connexion Google impossible'), findsOneWidget);
      expect(find.text('Continuer avec Google'), findsNothing);
    });

    testWidgets('an answer arriving while the sheet closes leaves the list in place', (tester) async {
      final attente = Completer<void>();
      final compte = _CompteLent(() => attente.future);
      await accueil(tester, FauxDepot([echeance()]), compte);
      await ouvrirCompte(tester);
      await tester.tap(find.text('Se déconnecter'));
      await tester.pump();
      await tester.tapAt(const Offset(10, 10)); // Outside: the sheet starts closing.
      await tester.pump(const Duration(milliseconds: 20));
      attente.complete();
      await tester.pumpAndSettle();
      expect(find.byType(BoutonCompte), findsOneWidget);
    });

    testWidgets('sign-out failing is explained', (tester) async {
      await accueil(tester, FauxDepot([echeance()]), _CompteLent(() async => throw StateError('panne')));
      await ouvrirCompte(tester);
      await tester.tap(find.text('Se déconnecter'));
      await tester.pumpAndSettle();
      expect(find.text('Déconnexion impossible'), findsOneWidget);
    });

    testWidgets('a Google failure is explained and the user stays where they were', (tester) async {
      var redemarrages = 0;
      final compte = FauxCompte(erreur: const CompteImpossible('Réessaie.'));
      await accueil(tester, FauxDepot([echeance()]), compte, onCompteChange: () => redemarrages++);
      await continuerAvecGoogle(tester);
      expect(find.text('Connexion Google impossible'), findsOneWidget);
      expect(redemarrages, 0);
    });

    testWidgets('closing the Google window changes nothing', (tester) async {
      var redemarrages = 0;
      final compte = FauxCompte(resultat: ResultatGoogle.annule);
      await accueil(tester, FauxDepot([echeance()]), compte, onCompteChange: () => redemarrages++);
      await continuerAvecGoogle(tester);
      expect(find.byType(SnackBar), findsNothing);
      expect(redemarrages, 0);
    });

    testWidgets('connected: the address is only in the menu, with change and sign-out', (tester) async {
      final compte = FauxCompte(estAnonyme: false, email: 'camille@exemple.fr');
      await accueil(tester, FauxDepot([echeance()]), compte);
      expect(find.textContaining('camille@exemple.fr'), findsNothing, reason: 'nothing about it on the list');
      await ouvrirCompte(tester);
      expect(find.text('camille@exemple.fr'), findsOneWidget);
      expect(find.text('Changer de compte'), findsOneWidget);
      expect(find.text('Continuer avec Google'), findsNothing);
    });

    testWidgets('signing out and changing account restart the app on the new session', (tester) async {
      var redemarrages = 0;
      final compte = FauxCompte(estAnonyme: false, email: 'camille@exemple.fr', resultat: ResultatGoogle.connecte);
      await accueil(tester, FauxDepot([echeance()]), compte, onCompteChange: () => redemarrages++);
      await ouvrirCompte(tester);
      await tester.tap(find.text('Changer de compte'));
      await tester.pumpAndSettle();
      await ouvrirCompte(tester);
      await tester.tap(find.text('Se déconnecter'));
      await tester.pumpAndSettle();
      expect(compte.appels, ['changer', 'deconnecter']);
      expect(redemarrages, 2);
      expect(find.text('Se déconnecter'), findsNothing, reason: 'the sheet is closed');
    });

    testWidgets('no account (demo): no account button', (tester) async {
      await accueil(tester, FauxDepot([echeance()]), null);
      expect(find.byTooltip('Mon compte'), findsNothing);
    });
  });

  testWidgets('every way to add a letter is in the sheet, over the list', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(appli(FauxDepot([echeance()])));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter un courrier'));
    await tester.pumpAndSettle();
    for (final option in [
      'Prendre une photo',
      'Choisir dans mes photos',
      'Importer un fichier',
      'Coller le texte',
      'Saisir à la main',
    ]) {
      expect(find.text(option), findsOneWidget, reason: option);
    }
    expect(
      find.text('Payer l\'amende', skipOffstage: false),
      findsOneWidget,
      reason: 'the list stays behind the sheet',
    );
    expect(find.text('Une amende'), findsNothing, reason: 'fictional letters are for the demo only');
  });

  testWidgets('tapping outside a field closes the keyboard', (tester) async {
    await tester.pumpWidget(appli(FauxDepot(), lecteur: FauxLecteur(reponse: lecture())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter un courrier'));
    await tester.pumpAndSettle();
    await montrerDansLaFeuille(tester, find.text('Saisir à la main'));
    await tester.tap(find.text('Saisir à la main'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tapAt(const Offset(4, 300));
    await tester.pump();
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('a notice with an action still leaves by itself', (tester) async {
    await tester.pumpWidget(appli(FauxDepot([echeance()])));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Payer l\'amende'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('C\'est fait'));
    await tester.pumpAndSettle();
    expect(find.text('Marqué comme fait'), findsOneWidget);
    expect(find.text('Annuler'), findsOneWidget);
    final enPlace = tester.getTopLeft(find.text('Marqué comme fait')).dy;
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.getTopLeft(find.text('Marqué comme fait')).dy, greaterThan(enPlace), reason: 'it leaves downwards');
    await tester.pumpAndSettle();
    expect(find.text('Marqué comme fait'), findsNothing);
  });

  testWidgets('opening the add sheet wakes the backend and names who reads the letter', (tester) async {
    final lecteur = FauxLecteur();
    await tester.pumpWidget(
      MaterialApp(
        theme: themePli(),
        home: Scaffold(
          body: FeuilleAjout(depot: FauxDepot(), lecteur: lecteur, maintenant: () => aujourdhui),
        ),
      ),
    );
    await tester.pump();
    expect(lecteur.reveils, 1);
    expect(find.textContaining('Claude (Anthropic)'), findsOneWidget);
  });

  /// Goes from the list to the save button, through the whole app.
  Future<void> jusquAEnregistrer(WidgetTester tester, FauxDepot depot) async {
    await tester.pumpWidget(appli(depot, lecteur: FauxLecteur(reponse: lecture())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter un courrier'));
    await tester.pumpAndSettle();
    await lireUnTexte(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer l\'échéance'));
    await tester.pump();
  }

  Future<void> jusquAuRetourSansReseau(WidgetTester tester, FauxDepot depot) async {
    await jusquAEnregistrer(tester, depot);
    await tester.pump(attenteEnregistrement + const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('Pas encore enregistrée'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  testWidgets('saving without network never announces a success, and never writes twice', (tester) async {
    final depot = _DepotSansReseau();
    await jusquAuRetourSansReseau(tester, depot);

    expect(find.text('Ajouter un courrier'), findsOneWidget, reason: 'back to the list');
    expect(find.text('Échéance enregistrée'), findsNothing);
    expect(depot.ajoutees, hasLength(1));

    depot.reponse.complete();
    await tester.pumpAndSettle();
    expect(find.text('Échéance enregistrée'), findsOneWidget, reason: 'the server has it now');
  });

  testWidgets('a write refused after the wait is still reported', (tester) async {
    final depot = _DepotSansReseau();
    await jusquAuRetourSansReseau(tester, depot);

    depot.reponse.completeError(Exception('permission-denied'));
    await tester.pumpAndSettle();
    expect(find.text('Échéance non enregistrée'), findsOneWidget);
    expect(find.textContaining('ajoute-la de nouveau'), findsOneWidget);
    expect(find.text('Échéance enregistrée'), findsNothing);
  });

  testWidgets('going back is blocked while a save is waiting for its answer', (tester) async {
    final depot = _DepotSansReseau();
    await jusquAEnregistrer(tester, depot);
    await tester.tap(find.byType(BackButton));
    await tester.pump(); // a first frame starts the page transition, the next one ends it
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Vérifie avant d\'enregistrer'), findsOneWidget);
    await tester.pump(attenteEnregistrement);
    await tester.pump();
  });

  testWidgets('an unexpected failure while saving is shown, and the screen stays usable', (tester) async {
    final depot = _DepotCasse();
    await jusquAEnregistrer(tester, depot);
    await tester.pumpAndSettle();
    expect(find.text('Enregistrement impossible'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Vérifie avant d\'enregistrer'), findsNothing, reason: 'the user can leave');
  });

  testWidgets('coming back to the app the next day updates the countdown', (tester) async {
    var jour = DateTime(2026, 10, 17);
    await tester.pumpWidget(PliApp(depot: FauxDepot([echeance()]), lecteur: FauxLecteur(), maintenant: () => jour));
    await tester.pumpAndSettle();
    expect(find.text('Demain'), findsOneWidget);
    jour = DateTime(2026, 10, 18);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Aujourd\'hui'), findsOneWidget);
  });

  testWidgets('the list keeps one Firestore listener when the screen rebuilds', (tester) async {
    final depot = _DepotCompteur();
    await tester.pumpWidget(appli(depot));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(depot.ecoutes, 1);
  });

  testWidgets('after a change of account, nothing says the new list is empty before it has answered', (tester) async {
    await tester.pumpWidget(appli(FauxDepot()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Aucun courrier'), findsOneWidget);
    await tester.pumpWidget(appli(_DepotMuet()));
    await tester.pump();
    expect(find.textContaining('Aucun courrier'), findsNothing);
    expect(find.text('Chargement… Vérifie ta connexion si ça dure.'), findsOneWidget);
  });

  test('an empty cache only hides the list until it has been loaded once', () {
    List<bool> suite(List<(bool, bool)> instantanes) {
      final filtre = filtreListeChargee();
      return [for (final (vide, duCache) in instantanes) filtre(vide: vide, duCache: duCache)];
    }

    expect(suite([(true, true)]), [false], reason: 'offline start');
    expect(suite([(true, true), (true, false)]), [false, true], reason: 'the server says it is really empty');
    expect(suite([(false, true), (true, true)]), [true, true], reason: 'last item deleted offline');
    expect(suite([(true, false), (true, true)]), [true, true], reason: 'empty, then the connection drops');
  });

  testWidgets('after a change of account, the list shown is the new account\'s', (tester) async {
    await tester.pumpWidget(appli(FauxDepot([echeance(titre: 'Liste du téléphone')])));
    await tester.pumpAndSettle();
    expect(find.text('Liste du téléphone'), findsOneWidget);
    await tester.pumpWidget(appli(FauxDepot([echeance(titre: 'Liste Google')])));
    await tester.pumpAndSettle();
    expect(find.text('Liste Google'), findsOneWidget);
    expect(find.text('Liste du téléphone'), findsNothing);
  });

  testWidgets('an information letter closes with « Compris » and saves nothing', (tester) async {
    final depot = FauxDepot();
    await tester.pumpWidget(
      appli(
        depot,
        lecteur: FauxLecteur(reponse: lecture(action: 'aucune', sansDate: true)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter un courrier'));
    await tester.pumpAndSettle();
    await lireUnTexte(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compris'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Compris'), findsNothing);
    expect(find.text('Échéance enregistrée'), findsNothing);
    expect(depot.ajoutees, isEmpty);
  });

  testWidgets('without any reading, a deadline can be entered by hand', (tester) async {
    final depot = FauxDepot();
    await tester.pumpWidget(appli(depot));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter un courrier'));
    await tester.pumpAndSettle();
    await montrerDansLaFeuille(tester, find.text('Saisir à la main'));
    await tester.tap(find.text('Saisir à la main'));
    await tester.pumpAndSettle();
    expect(find.text('CE QUE PLI A LU'), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'Renvoyer le dossier');
    await tester.tap(find.text('Choisir une date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer l\'échéance'));
    await tester.pumpAndSettle();
    expect(depot.ajoutees.single.titre, 'Renvoyer le dossier');
    expect(depot.ajoutees.single.source, 'manuel');
    expect(depot.ajoutees.single.aVerifier, isFalse);
    expect(find.text('Échéance enregistrée'), findsOneWidget);
  });

  for (final faux in ['1.234', '87,425', '1e5', '-0', '-5', '1000000', 'abc']) {
    testWidgets('an amount like $faux is refused, not saved as something else', (tester) async {
      final depot = FauxDepot();
      await tester.pumpWidget(verification(depot, l: lecture()));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Montant (facultatif)'), faux);
      await tester.tap(find.text('Enregistrer l\'échéance'));
      await tester.pumpAndSettle();
      expect(depot.ajoutees, isEmpty);
      expect(find.text('Écris un montant comme 90 ou 87,42'), findsOneWidget);
    });
  }

  for (final (saisie, valeur) in [('90', 90.0), ('87,42', 87.42), ('1 234,5 €', 1234.5), ('12.50', 12.5)]) {
    testWidgets('the amount $saisie is saved as $valeur', (tester) async {
      final depot = FauxDepot();
      await tester.pumpWidget(verification(depot, l: lecture()));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Montant (facultatif)'), saisie);
      await tester.tap(find.text('Enregistrer l\'échéance'));
      await tester.pumpAndSettle();
      expect(depot.ajoutees.single.montant, valeur);
    });
  }

  testWidgets('a deadline entered by hand shows no sender and no empty summary', (tester) async {
    final depot = FauxDepot([
      Echeance(
        id: 'm',
        organisme: 'autre',
        organismeNom: 'Saisie à la main',
        action: 'demander',
        titre: 'Renvoyer le dossier',
        dateLimite: DateTime(2026, 10, 25),
        montant: null,
        resume: '',
        aVerifier: false,
        source: 'manuel',
        fait: false,
      ),
    ]);
    await tester.pumpWidget(appli(depot));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Renvoyer le dossier'));
    await tester.pumpAndSettle();
    expect(find.text('C\'est fait'), findsOneWidget);
    expect(find.text('Saisie à la main'), findsNothing);
  });

  testWidgets('the wait for the list says what to check', (tester) async {
    final depot = _DepotMuet();
    await tester.pumpWidget(appli(depot));
    await tester.pump();
    expect(find.text('Chargement… Vérifie ta connexion si ça dure.'), findsOneWidget);
    expect(find.textContaining('Aucun courrier'), findsNothing);
  });

  group('a change refused by the server is reported', () {
    Future<void> ouvrirDetail(WidgetTester tester, FauxDepot depot) async {
      await tester.pumpWidget(appli(depot));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Payer l\'amende'));
      await tester.pumpAndSettle();
    }

    testWidgets('marking as done', (tester) async {
      await ouvrirDetail(tester, _DepotCasse([echeance()]));
      await tester.tap(find.text('C\'est fait'));
      await tester.pumpAndSettle();
      expect(find.text('Modification impossible'), findsOneWidget);
    });

    testWidgets('undoing', (tester) async {
      final depot = _DepotCasseEnSuite([echeance()]);
      await ouvrirDetail(tester, depot);
      await tester.tap(find.text('C\'est fait'));
      await tester.pumpAndSettle();
      expect(find.text('Marqué comme fait'), findsOneWidget);
      depot.casse = true;
      await tester.tap(find.text('Annuler'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Modification impossible'), findsOneWidget);
    });

    testWidgets('deleting', (tester) async {
      await ouvrirDetail(tester, _DepotCasse([echeance()]));
      await tester.ensureVisible(find.text('Supprimer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer').last);
      await tester.pumpAndSettle();
      expect(find.text('Modification impossible'), findsOneWidget);
    });
  });

  test('bornerTexte never cuts an emoji in half', () {
    expect(bornerTexte('abc', 5), 'abc');
    expect(bornerTexte('abcdef', 3), 'abc');
    expect(bornerTexte('ab😀cd', 3), 'ab');
    expect(bornerTexte('ab😀cd', 4), 'ab😀');
  });
}

/// Answers only when the test says so, like a backend waking up.
class _LecteurLent extends FauxLecteur {
  final attendue = Completer<Lecture>();

  @override
  Future<Lecture> lire(CourrierAEnvoyer courrier) => attendue.future;
}

/// Fails the way no screen expects (a token refresh, a bug): the user must still be told.
class _LecteurEnPanne extends FauxLecteur {
  @override
  Future<Lecture> lire(CourrierAEnvoyer courrier) async => throw StateError('jeton introuvable');
}

/// Every write fails, even before returning a future.
class _DepotCasse extends FauxDepot {
  _DepotCasse([super.depart]);

  @override
  Future<void> ajouter(Echeance e) => throw StateError('inattendu');

  @override
  Future<void> marquerFait(String id, bool fait) => throw StateError('refusé');

  @override
  Future<void> supprimer(String id) => throw StateError('refusé');
}

class _DepotCasseEnSuite extends FauxDepot {
  _DepotCasseEnSuite([super.depart]);

  var casse = false;

  @override
  Future<void> marquerFait(String id, bool fait) async {
    if (casse) throw StateError('refusé');
  }
}

class _DepotCompteur extends FauxDepot {
  var ecoutes = 0;

  @override
  Stream<List<Echeance>> surveiller() {
    ecoutes++;
    return super.surveiller();
  }
}

class _DepotSansReseau extends FauxDepot {
  final reponse = Completer<void>();

  @override
  Future<void> ajouter(Echeance e) {
    ajoutees.add(e);
    return reponse.future;
  }
}

class _DepotMuet extends FauxDepot {
  @override
  Stream<List<Echeance>> surveiller() => const Stream.empty();
}
