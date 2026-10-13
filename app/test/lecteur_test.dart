import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pli/services/lecteur_courrier.dart';

const reponseOk = {
  'extraction': {
    'organisme': 'antai',
    'organisme_nom': 'ANTAI',
    'action': 'payer',
    'titre': "Payer l'amende",
    'date_limite': '2026-10-18',
    'montant': 90,
    'date_courrier': '2026-10-03',
    'resume': 'Paie 90 €.',
    'a_verifier': false,
    'raison_verification': null,
  },
  'source': 'claude',
  'modele': 'claude-opus-5-5',
};

/// Like FastAPI: JSON encoded as UTF-8.
http.Response json(Object corps, int code) =>
    http.Response.bytes(utf8.encode(jsonEncode(corps)), code, headers: {'content-type': 'application/json'});

LecteurHttp lecteur(MockClient client) => LecteurHttp(
  urlApi: Uri.parse('https://api.pli.test'),
  jeton: () async => 'jeton-1',
  client: client,
  maintenant: () => DateTime(2026, 10, 12, 23, 30),
);

void main() {
  test('sends the letter with the Firebase token and reads the answer', () async {
    late http.Request recue;
    final client = MockClient((r) async {
      recue = r;
      return json(reponseOk, 200);
    });
    final l = await lecteur(client).lire(const CourrierTexte('Avis de contravention'));
    expect(recue.url.toString(), 'https://api.pli.test/v1/extractions');
    expect(recue.headers['Authorization'], 'Bearer jeton-1');
    expect(jsonDecode(recue.body), {'texte': 'Avis de contravention', 'recu_le': '2026-10-12'});
    expect(l.montant, 90.0);
  });

  test('files go as base64', () async {
    late Map<String, dynamic> corps;
    final client = MockClient((r) async {
      corps = jsonDecode(r.body) as Map<String, dynamic>;
      return json(reponseOk, 200);
    });
    await lecteur(client).lire(CourrierFichier(mediaType: 'application/pdf', octets: Uint8List.fromList([1, 2, 3])));
    expect(corps['fichier'], {'media_type': 'application/pdf', 'donnees_base64': 'AQID'});
  });

  test("the backend's message is shown to the user", () async {
    final client = MockClient(
      (_) async => json({'detail': 'Trop de courriers d\'un coup, réessaie dans une minute'}, 429),
    );
    expect(
      () => lecteur(client).lire(const CourrierTexte('x')),
      throwsA(isA<LectureImpossible>().having((e) => e.message, 'message', contains('réessaie dans une minute'))),
    );
  });

  test('validation errors get a generic message instead of raw details', () async {
    final client = MockClient(
      (_) async => json({
        'detail': [
          {'msg': 'x'},
        ],
      }, 422),
    );
    expect(
      () => lecteur(client).lire(const CourrierTexte('x')),
      throwsA(isA<LectureImpossible>().having((e) => e.message, 'message', contains('erreur 422'))),
    );
  });

  test('a network failure becomes an actionable message', () async {
    final client = MockClient((_) async => throw http.ClientException('hors ligne'));
    expect(
      () => lecteur(client).lire(const CourrierTexte('x')),
      throwsA(isA<LectureImpossible>().having((e) => e.message, 'message', contains('connexion'))),
    );
  });

  test('files over 5 MB are refused before upload', () async {
    var appels = 0;
    final client = MockClient((_) async {
      appels++;
      return http.Response('{}', 200);
    });
    final gros = CourrierFichier(mediaType: 'image/jpeg', octets: Uint8List(tailleMaxOctets + 1));
    await expectLater(() => lecteur(client).lire(gros), throwsA(isA<LectureImpossible>()));
    expect(appels, 0);
  });
}
