import 'package:cloud_firestore/cloud_firestore.dart';

import '../modeles/echeance.dart';

abstract interface class DepotEcheances {
  Stream<List<Echeance>> surveiller();
  Future<void> ajouter(Echeance echeance);
  Future<void> marquerFait(String id, bool fait);
  Future<void> supprimer(String id);
}

/// An account's deadlines, read and copied when a device's list joins a Google account's list.
abstract interface class ListeDeCompte {
  Future<List<Echeance>> lister();
  Future<void> reprendre(List<Echeance> echeances);
}

/// Without network, an empty cache at the start is not an empty list: wait rather than say there is nothing to do.
/// Once a list is shown, every change counts, like deleting its last item offline.
bool Function({required bool vide, required bool duCache}) filtreListeChargee() {
  var chargee = false;
  return ({required vide, required duCache}) => chargee = chargee || !vide || !duCache;
}

class DepotFirestore implements DepotEcheances, ListeDeCompte {
  DepotFirestore(this._db, this._uid);

  final FirebaseFirestore _db;
  final String _uid;

  CollectionReference<Map<String, dynamic>> get _echeances => _db.collection('users').doc(_uid).collection('echeances');

  @override
  Stream<List<Echeance>> surveiller() {
    final chargee = filtreListeChargee();
    return _echeances
        .orderBy('dateLimite')
        .snapshots(includeMetadataChanges: true)
        .where((s) => chargee(vide: s.docs.isEmpty, duCache: s.metadata.isFromCache))
        .map((s) => [for (final d in s.docs) Echeance.depuisFirestore(d.id, d.data())]);
  }

  @override
  Future<void> ajouter(Echeance echeance) => _echeances.add(echeance.versFirestore());

  @override
  Future<void> marquerFait(String id, bool fait) => _echeances.doc(id).update({'fait': fait});

  @override
  Future<void> supprimer(String id) => _echeances.doc(id).delete();

  @override
  Future<List<Echeance>> lister() async {
    final s = await _echeances.get();
    return [for (final d in s.docs) Echeance.depuisFirestore(d.id, d.data())];
  }

  /// Safe to run again after a refusal: a copy keeps the deadline's id, and what is already there is not rewritten.
  /// The rules only let a deadline be created as not done: the ones already done are ticked in a second write.
  /// Both are queued at once: without network, awaiting the first would leave the second unsent.
  /// shortcut: Android may commit them in either order, a refused tick then goes through the retry; one batch holds 500
  /// writes, far above a personal list. Revisit both if Android ships or lists get that long.
  @override
  Future<void> reprendre(List<Echeance> echeances) async {
    final deja = {for (final d in (await _echeances.get()).docs) d.id: d.data()['fait'] as bool};
    final creations = _db.batch();
    final faites = _db.batch();
    for (final e in echeances) {
      final copie = _echeances.doc(e.id);
      if (!deja.containsKey(e.id)) creations.set(copie, e.versFirestore());
      if (e.fait && deja[e.id] != true) faites.update(copie, {'fait': true});
    }
    await Future.wait([creations.commit(), faites.commit()]);
  }
}
