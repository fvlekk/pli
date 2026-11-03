import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pli/app.dart';
import 'package:pli/ecrans/ajout.dart';
import 'package:pli/ecrans/demarrage.dart';
import 'package:pli/ecrans/verification.dart';
import 'package:pli/modeles/lecture.dart';
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
    await tester.scrollUntilVisible(find.text('Une amende'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Une amende'));
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
    await tester.scrollUntilVisible(find.text('Une amende'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Une amende'));
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
    // Tall enough that the status line at the top stays built while an example at the bottom is tapped.
    await tester.binding.setSurfaceSize(const Size(420, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final lecteur = _LecteurLent();
    await tester.pumpWidget(PliApp(depot: FauxDepot(), lecteur: lecteur, maintenant: () => aujourdhui));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter un courrier'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Une amende'));
    await tester.pump();
    expect(find.text('Je lis ton courrier…'), findsOneWidget);
    await tester.pump(attenteLente + const Duration(seconds: 1));
    expect(find.text('Le service se réveille, ça peut prendre une minute…'), findsOneWidget);
    lecteur.reponse.complete(lecture());
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
    await tester.tap(find.text('Une amende'));
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

    testWidgets('an anonymous list can be kept with Google, same account', (tester) async {
      final compte = FauxCompte();
      await accueil(tester, FauxDepot([echeance()]), compte);
      await tester.tap(find.text('Garder mes échéances avec Google'));
      await tester.pumpAndSettle();
      expect(compte.demandes, [false], reason: 'deadlines here: link, never replace');
      expect(find.text('Échéances gardées avec Google'), findsOneWidget);
      expect(find.text('Garder mes échéances avec Google'), findsNothing);
    });

    testWidgets('on an empty phone, Google opens the list kept elsewhere and the app restarts on it', (tester) async {
      var redemarrages = 0;
      final compte = FauxCompte(resultat: ResultatGoogle.connecte);
      await accueil(tester, FauxDepot(), compte, onCompteChange: () => redemarrages++);
      await tester.tap(find.text('Retrouver mes échéances avec Google'));
      await tester.pumpAndSettle();
      expect(compte.demandes, [true]);
      expect(redemarrages, 1);
    });

    testWidgets('two lists are never merged silently: the user is told why', (tester) async {
      final compte = FauxCompte(erreur: const CompteImpossible('Ce compte Google a déjà sa propre liste.'));
      await accueil(tester, FauxDepot([echeance()]), compte);
      await tester.tap(find.text('Garder mes échéances avec Google'));
      await tester.pumpAndSettle();
      expect(find.text('Ce compte Google a déjà sa propre liste.'), findsOneWidget);
      expect(find.text('Garder mes échéances avec Google'), findsOneWidget, reason: 'still anonymous');
    });

    testWidgets('closing the Google window changes nothing', (tester) async {
      var redemarrages = 0;
      final compte = FauxCompte(resultat: ResultatGoogle.annule);
      await accueil(tester, FauxDepot([echeance()]), compte, onCompteChange: () => redemarrages++);
      await tester.tap(find.text('Garder mes échéances avec Google'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(redemarrages, 0);
      expect(find.text('Garder mes échéances avec Google'), findsOneWidget);
    });

    testWidgets('a Google account shows where the list is kept', (tester) async {
      await accueil(tester, FauxDepot([echeance()]), FauxCompte(estAnonyme: false, email: 'camille@exemple.fr'));
      expect(find.text('Échéances gardées avec camille@exemple.fr.'), findsOneWidget);
      expect(find.text('Garder mes échéances avec Google'), findsNothing);
    });

    testWidgets('no account (demo): no Google card', (tester) async {
      await accueil(tester, FauxDepot([echeance()]), null);
      expect(find.textContaining('avec Google'), findsNothing);
    });
  });
}

/// Answers only when the test says so, like a backend waking up.
class _LecteurLent implements LecteurCourrier {
  final reponse = Completer<Lecture>();

  @override
  Future<Lecture> lire(CourrierAEnvoyer courrier) => reponse.future;
}

/// Fails the way no screen expects (a token refresh, a bug): the user must still be told.
class _LecteurEnPanne implements LecteurCourrier {
  @override
  Future<Lecture> lire(CourrierAEnvoyer courrier) async => throw StateError('jeton introuvable');
}
