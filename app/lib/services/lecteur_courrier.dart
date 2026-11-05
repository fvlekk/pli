import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config.dart';
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
  LecteurHttp({
    required this.urlApi,
    required this.jeton,
    this.jetonApp,
    http.Client? client,
    this.maintenant = DateTime.now,
  }) : _client = client ?? http.Client();

  final Uri urlApi;
  final Future<String> Function() jeton;

  /// App Check token: proves the call comes from this app, not from a script with a free anonymous account.
  final Future<String?> Function()? jetonApp;
  final DateTime Function() maintenant;
  final http.Client _client;

  @override
  Future<Lecture> lire(CourrierAEnvoyer courrier) async {
    if (courrier case CourrierFichier(:final octets) when octets.length > tailleMaxOctets) {
      throw const LectureImpossible('Ce fichier dépasse 5 Mo. Prends une photo plus légère ou colle le texte.');
    }
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

    final String connexion;
    try {
      connexion = await jeton();
    } catch (_) {
      // Renewing the sign-in token needs the network and, with App Check enforced, a fresh attestation.
      throw const LectureImpossible('Ta connexion à Pli a expiré : recharge la page, puis réessaie.');
    }

    final http.Response reponse;
    try {
      final app = await _jetonApp();
      reponse = await _client
          .post(
            urlApi.resolve('/v1/extractions'),
            headers: {
              'Authorization': 'Bearer $connexion',
              'Content-Type': 'application/json',
              if (app != null && app.isNotEmpty) 'X-Firebase-AppCheck': app,
            },
            body: jsonEncode(corps),
          )
          .timeout(const Duration(seconds: 90));
    } on TimeoutException {
      throw const LectureImpossible('La lecture prend trop de temps. Réessaie, ou saisis l\'échéance à la main.');
    } on http.ClientException catch (e) {
      // Temporary, iOS test builds only: this message hides why the call fails on the phone.
      final detail = Config.jetonDebugAppCheck.isEmpty ? '' : ' [$e]';
      throw LectureImpossible('Pas de connexion au service de lecture. Vérifie ta connexion et réessaie.$detail');
    }

    final json = _json(reponse);
    if (reponse.statusCode == 200 && json != null) return Lecture.depuisJson(json);
    final detail = json?['detail'];
    throw LectureImpossible(detail is String ? detail : 'Lecture impossible (erreur ${reponse.statusCode}).');
  }

  /// Without a token (reCAPTCHA blocked, App Check off) the request still goes: the backend decides.
  Future<String?> _jetonApp() async {
    try {
      return await jetonApp?.call();
    } catch (_) {
      return null;
    }
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
