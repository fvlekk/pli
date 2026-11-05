import 'package:cloud_firestore/cloud_firestore.dart';

import '../modeles/echeance.dart';

abstract interface class DepotEcheances {
  Stream<List<Echeance>> surveiller();
  Future<void> ajouter(Echeance echeance);
  Future<void> marquerFait(String id, bool fait);
  Future<void> supprimer(String id);
}

/// Without network, an empty cache at the start is not an empty list: wait rather than say there is nothing to do.
/// Once a list is shown, every change counts, like deleting its last item offline.
bool Function({required bool vide, required bool duCache}) filtreListeChargee() {
  var chargee = false;
  return ({required vide, required duCache}) => chargee = chargee || !vide || !duCache;
}

class DepotFirestore implements DepotEcheances {
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
}
