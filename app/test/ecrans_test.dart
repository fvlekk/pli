import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pli/app.dart';
import 'package:pli/ecrans/verification.dart';
import 'package:pli/services/lecteur_courrier.dart';
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
    final positions = [for (final t in titres) tester.getTopLeft(find.text(t)).dy];
    expect(positions, orderedEquals([...positions]..sort()), reason: 'panels in time order');
    expect(find.text('Une démarche est en retard.'), findsOneWidget);
    expect(find.text('Fait (1)'), findsOneWidget);
    expect(find.text('Envoyer l\'attestation'), findsNothing, reason: 'done items stay folded');
    expect(find.text('90 €'), findsWidgets);
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
}
