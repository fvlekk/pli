import 'dart:async';

import '../modeles/echeance.dart';
import '../services/depot_echeances.dart';

/// Deadlines kept in memory, ordered by date like DepotFirestore. A reload starts over: demo only.
class DepotMemoire implements DepotEcheances {
  DepotMemoire([List<Echeance> depart = const []]) {
    for (final e in depart) {
      _ranger(e, fait: e.fait);
    }
  }

  /// Three made-up deadlines, one per home section: late, this week, this month.
  factory DepotMemoire.demo(DateTime aujourdhui) {
    DateTime dans(int jours) => DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day + jours);
    return DepotMemoire([
      Echeance(
        organisme: 'caf',
        organismeNom: 'Caf de la Gironde',
        action: 'declarer',
        titre: 'Déclarer tes ressources du trimestre',
        dateLimite: dans(-2),
        montant: null,
        resume: 'Déclare tes ressources des trois derniers mois sur caf.fr pour garder ta prime d\'activité.',
        aVerifier: false,
        fait: false,
        source: 'claude',
      ),
      Echeance(
        organisme: 'bailleur',
        organismeNom: 'Habitat Gironde',
        action: 'payer',
        titre: 'Payer les charges de l\'année',
        dateLimite: dans(4),
        montant: 146.30,
        resume: 'Paie 146,30 € de charges en plus pour l\'année, par virement ou sur ton espace locataire.',
        aVerifier: false,
        fait: false,
        source: 'claude',
      ),
      Echeance(
        organisme: 'france_travail',
        organismeNom: 'France Travail',
        action: 'se_presenter',
        titre: 'Aller au rendez-vous de suivi',
        dateLimite: dans(18),
        montant: null,
        resume: 'Présente-toi à l\'agence de Mérignac avec ta pièce d\'identité et ton CV à jour.',
        aVerifier: false,
        fait: false,
        source: 'claude',
      ),
    ]);
  }

  final _echeances = <String, Echeance>{};
  final _flux = StreamController<List<Echeance>>.broadcast();
  var _suivant = 0;

  @override
  Stream<List<Echeance>> surveiller() => Stream.multi((abonne) {
    abonne.add(_triees());
    final abonnement = _flux.stream.listen(abonne.add);
    abonne.onCancel = abonnement.cancel;
  });

  /// Like the Firestore create, a new deadline always starts not done.
  @override
  Future<void> ajouter(Echeance echeance) async {
    _ranger(echeance, fait: false);
    _publier();
  }

  @override
  Future<void> marquerFait(String id, bool fait) async {
    final e = _echeances[id];
    if (e == null) return;
    _echeances[id] = _avec(e, id: id, fait: fait);
    _publier();
  }

  @override
  Future<void> supprimer(String id) async {
    _echeances.remove(id);
    _publier();
  }

  void _ranger(Echeance e, {required bool fait}) {
    final id = 'demo-${_suivant++}';
    _echeances[id] = _avec(e, id: id, fait: fait);
  }

  List<Echeance> _triees() => _echeances.values.toList()..sort((a, b) => a.dateLimite.compareTo(b.dateLimite));

  void _publier() => _flux.add(_triees());
}

Echeance _avec(Echeance e, {required String id, required bool fait}) => Echeance(
  id: id,
  organisme: e.organisme,
  organismeNom: e.organismeNom,
  action: e.action,
  titre: e.titre,
  dateLimite: e.dateLimite,
  montant: e.montant,
  resume: e.resume,
  aVerifier: e.aVerifier,
  fait: fait,
  source: e.source,
);
