import 'dart:async';

import 'package:pli/modeles/echeance.dart';
import 'package:pli/modeles/lecture.dart';
import 'package:pli/services/depot_echeances.dart';
import 'package:pli/services/lecteur_courrier.dart';

final aujourdhui = DateTime(2026, 10, 12);

Echeance echeance({
  String id = 'e1',
  String titre = 'Payer l\'amende',
  DateTime? dateLimite,
  double? montant = 90,
  bool fait = false,
  bool aVerifier = false,
}) => Echeance(
  id: id,
  organisme: 'antai',
  organismeNom: 'ANTAI',
  action: 'payer',
  titre: titre,
  dateLimite: dateLimite ?? DateTime(2026, 10, 18),
  montant: montant,
  resume: 'Paie 90 € avant le 18 octobre.',
  aVerifier: aVerifier,
  fait: fait,
  source: 'claude',
);

Lecture lecture({
  String titre = 'Payer l\'amende',
  String action = 'payer',
  DateTime? dateLimite,
  double? montant = 90,
  bool aVerifier = false,
  String? raison,
  String source = 'claude',
  bool sansDate = false,
}) => Lecture(
  organisme: 'antai',
  organismeNom: 'Agence nationale de traitement automatisé des infractions',
  action: action,
  titre: titre,
  dateLimite: sansDate ? null : (dateLimite ?? DateTime(2026, 10, 18)),
  montant: montant,
  resume: 'Paie 90 € avant le 18 octobre pour le tarif minoré.',
  aVerifier: aVerifier,
  raisonVerification: raison,
  source: source,
  modele: source == 'claude' ? 'claude-opus-5-5' : null,
);

class FauxDepot implements DepotEcheances {
  FauxDepot([List<Echeance> depart = const []]) : _echeances = [...depart];

  final List<Echeance> _echeances;
  final ajoutees = <Echeance>[];
  final _flux = StreamController<List<Echeance>>.broadcast();

  @override
  Stream<List<Echeance>> surveiller() async* {
    yield List.of(_echeances);
    yield* _flux.stream;
  }

  @override
  Future<void> ajouter(Echeance e) async {
    ajoutees.add(e);
    _echeances.add(e);
    _flux.add(List.of(_echeances));
  }

  @override
  Future<void> marquerFait(String id, bool fait) async {}

  @override
  Future<void> supprimer(String id) async {}
}

class FauxLecteur implements LecteurCourrier {
  FauxLecteur({this.reponse, this.erreur});

  final Lecture? reponse;
  final LectureImpossible? erreur;
  final recus = <CourrierAEnvoyer>[];

  @override
  Future<Lecture> lire(CourrierAEnvoyer courrier) async {
    recus.add(courrier);
    if (erreur != null) throw erreur!;
    return reponse!;
  }
}
