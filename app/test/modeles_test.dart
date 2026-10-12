import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pli/modeles/echeance.dart';
import 'package:pli/modeles/lecture.dart';

import 'faux.dart';

void main() {
  test('a deadline is stored at noon UTC and read back as the same day', () {
    final t = Echeance.jourVersTimestamp(DateTime(2026, 11, 15, 23, 30));
    expect(t.toDate().toUtc(), DateTime.utc(2026, 11, 15, 12));
    expect(Echeance.timestampVersJour(t), DateTime(2026, 11, 15));
  });

  test('the Firestore document has exactly the fields the rules allow', () {
    final doc = echeance(fait: true).versFirestore();
    expect(doc.keys.toSet(), {
      'organisme', 'organismeNom', 'action', 'titre', 'dateLimite', 'montant', 'resume', 'aVerifier', 'fait',
      'source', 'creeLe', //
    });
    expect(doc['fait'], isFalse, reason: 'the rules refuse a deadline created as done');
    expect(doc['creeLe'], isA<FieldValue>(), reason: 'the creation date must be the server time');
  });

  test('reads a deadline back from Firestore', () {
    final e = Echeance.depuisFirestore('x', {
      ...echeance().versFirestore(),
      'montant': 90, // Firestore returns an int for a whole number
      'creeLe': Timestamp.now(),
    });
    expect(e.id, 'x');
    expect(e.montant, 90.0);
    expect(e.dateLimite, DateTime(2026, 10, 18));
  });

  test('parses the backend answer', () {
    final l = Lecture.depuisJson({
      'extraction': {
        'organisme': 'caf',
        'organisme_nom': 'Caf de Paris',
        'action': 'declarer',
        'titre': 'Déclarer tes ressources',
        'date_limite': '2026-11-05',
        'montant': null,
        'date_courrier': '2026-10-06',
        'resume': 'Déclare tes ressources avant le 5 novembre.',
        'a_verifier': false,
        'raison_verification': null,
      },
      'source': 'regle',
      'modele': null,
    });
    expect(l.dateLimite, DateTime(2026, 11, 5));
    expect(l.montant, isNull);
    expect(l.aUneEcheance, isTrue);
  });

  test('an information letter has no deadline', () {
    expect(lecture(action: 'aucune').aUneEcheance, isFalse);
    expect(lecture(sansDate: true).aUneEcheance, isFalse);
  });
}
