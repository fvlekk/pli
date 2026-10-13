import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../modeles/lecture.dart';

sealed class CourrierAEnvoyer {
  const CourrierAEnvoyer();
}

class CourrierTexte extends CourrierAEnvoyer {
  const CourrierTexte(this.texte);
  final String texte;
}

class CourrierFichier extends CourrierAEnvoyer {
  const CourrierFichier({required this.mediaType, required this.octets});
  final String mediaType;
  final Uint8List octets;
}

/// A failure the user can act on; `message` is shown as is.
class LectureImpossible implements Exception {
  const LectureImpossible(this.message);
  final String message;

  @override
  String toString() => message;
}

abstract interface class LecteurCourrier {
  Future<Lecture> lire(CourrierAEnvoyer courrier);
}

const tailleMaxOctets = 5 * 1024 * 1024;

class LecteurHttp implements LecteurCourrier {
  LecteurHttp({required this.urlApi, required this.jeton, http.Client? client, this.maintenant = DateTime.now})
    : _client = client ?? http.Client();

  final Uri urlApi;
  final Future<String> Function() jeton;
  final DateTime Function() maintenant;
  final http.Client _client;

  @override
  Future<Lecture> lire(CourrierAEnvoyer courrier) async {
    final aujourdhui = maintenant();
    final corps = {
      ...switch (courrier) {
        CourrierTexte(:final texte) => {'texte': texte},
        CourrierFichier(:final mediaType, :final octets) => {
          'fichier': {'media_type': mediaType, 'donnees_base64': base64Encode(octets)},
        },
      },
      // The user's own day: "within 15 days of receipt" counts from here (the backend allows ±1 day).
      'recu_le': DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day).toIso8601String().substring(0, 10),
    };
    if (courrier case CourrierFichier(:final octets) when octets.length > tailleMaxOctets) {
      throw const LectureImpossible('Ce fichier dépasse 5 Mo. Prends une photo plus légère ou colle le texte.');
    }

    final http.Response reponse;
    try {
      reponse = await _client
          .post(
            urlApi.resolve('/v1/extractions'),
            headers: {'Authorization': 'Bearer ${await jeton()}', 'Content-Type': 'application/json'},
            body: jsonEncode(corps),
          )
          .timeout(const Duration(seconds: 90));
    } on TimeoutException {
      throw const LectureImpossible('La lecture prend trop de temps. Réessaie, ou saisis l\'échéance à la main.');
    } on http.ClientException {
      throw const LectureImpossible('Pas de connexion au service de lecture. Vérifie ta connexion et réessaie.');
    }

    final json = _json(reponse);
    if (reponse.statusCode == 200 && json != null) return Lecture.depuisJson(json);
    final detail = json?['detail'];
    throw LectureImpossible(detail is String ? detail : 'Lecture impossible (erreur ${reponse.statusCode}).');
  }

  Map<String, dynamic>? _json(http.Response reponse) {
    try {
      final valeur = jsonDecode(utf8.decode(reponse.bodyBytes));
      return valeur is Map<String, dynamic> ? valeur : null;
    } on FormatException {
      return null;
    }
  }
}
