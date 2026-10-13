import 'package:cloud_firestore/cloud_firestore.dart';

import '../modeles/echeance.dart';

abstract interface class DepotEcheances {
  Stream<List<Echeance>> surveiller();
  Future<void> ajouter(Echeance echeance);
  Future<void> marquerFait(String id, bool fait);
  Future<void> supprimer(String id);
}

class DepotFirestore implements DepotEcheances {
  DepotFirestore(this._db, this._uid);

  final FirebaseFirestore _db;
  final String _uid;

  CollectionReference<Map<String, dynamic>> get _echeances => _db.collection('users').doc(_uid).collection('echeances');

  @override
  Stream<List<Echeance>> surveiller() => _echeances
      .orderBy('dateLimite')
      .snapshots()
      .map((s) => [for (final d in s.docs) Echeance.depuisFirestore(d.id, d.data())]);

  @override
  Future<void> ajouter(Echeance echeance) => _echeances.add(echeance.versFirestore());

  @override
  Future<void> marquerFait(String id, bool fait) => _echeances.doc(id).update({'fait': fait});

  @override
  Future<void> supprimer(String id) => _echeances.doc(id).delete();
}
