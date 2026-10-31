import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pli/demo/depot_memoire.dart';
import 'package:pli/demo/lecteur_demo.dart';
import 'package:pli/exemples.dart';
import 'package:pli/outils/dates.dart';
import 'package:pli/services/lecteur_courrier.dart';

import 'faux.dart';

void main() {
  group('DepotMemoire', () {
    test('lists deadlines by date and gives each an id', () async {
      final depot = DepotMemoire([
        echeance(titre: 'B', dateLimite: DateTime(2026, 11, 2)),
        echeance(titre: 'A', dateLimite: DateTime(2026, 10, 20)),
      ]);
      final liste = await depot.surveiller().first;
      expect([for (final e in liste) e.titre], ['A', 'B']);
      expect({for (final e in liste) e.id}, hasLength(2));
    });

    test('an added deadline shows up in order, not done', () async {
      final depot = DepotMemoire([echeance(titre: 'Plus tard', dateLimite: DateTime(2026, 12, 1))]);
      final listes = depot.surveiller();
      expect(
        listes,
        emitsInOrder([
          hasLength(1),
          predicate<List<dynamic>>((l) => l.first.titre == 'Avant' && l.first.fait == false),
        ]),
      );
      await Future<void>.delayed(Duration.zero);
      await depot.ajouter(echeance(titre: 'Avant', dateLimite: DateTime(2026, 10, 20), fait: true));
    });

    test('marks done and deletes', () async {
      final depot = DepotMemoire([echeance(titre: 'A'), echeance(titre: 'B')]);
      final [a, b] = await depot.surveiller().first;
      await depot.marquerFait(a.id!, true);
      await depot.supprimer(b.id!);
      final liste = await depot.surveiller().first;
      expect(liste.single.titre, 'A');
      expect(liste.single.fait, isTrue);
    });

    test('the demo fills the late, this week and this month sections', () async {
      final liste = await DepotMemoire.demo(aujourdhui).surveiller().first;
      expect(
        [for (final e in liste) horizonDe(joursRestants(e.dateLimite, aujourdhui))],
        [Horizon.enRetard, Horizon.cetteSemaine, Horizon.ceMois],
      );
    });
  });

  group('LecteurDemo', () {
    final lecteur = LecteurDemo(delai: Duration.zero);

    test('reads every sample letter', () async {
      for (final exemple in exemples) {
        final lecture = await lecteur.lire(CourrierTexte(exemple.texte));
        expect(lecture.aUneEcheance, isTrue, reason: exemple.titre);
      }
      final amende = await lecteur.lire(CourrierTexte(exemples.first.texte));
      expect(amende.dateLimite, DateTime(2026, 10, 18));
      expect(amende.montant, 90);
    });

    test('refuses any other text, photo or PDF', () async {
      final refus = throwsA(
        isA<LectureImpossible>().having((e) => e.message, 'message', 'Mode démo : essaie un des courriers d\'exemple.'),
      );
      await expectLater(lecteur.lire(const CourrierTexte('Un autre courrier')), refus);
      await expectLater(lecteur.lire(CourrierFichier(mediaType: 'image/jpeg', octets: Uint8List(4))), refus);
      await expectLater(lecteur.lire(CourrierFichier(mediaType: 'application/pdf', octets: Uint8List(4))), refus);
    });
  });
}
