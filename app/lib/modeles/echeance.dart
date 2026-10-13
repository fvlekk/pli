import 'package:cloud_firestore/cloud_firestore.dart';

/// A confirmed deadline, stored at users/{uid}/echeances/{id}. Field names match firestore.rules.
class Echeance {
  const Echeance({
    this.id,
    required this.organisme,
    required this.organismeNom,
    required this.action,
    required this.titre,
    required this.dateLimite,
    required this.montant,
    required this.resume,
    required this.aVerifier,
    required this.fait,
    required this.source,
  });

  final String? id;
  final String organisme;
  final String organismeNom;
  final String action;
  final String titre;

  /// A calendar day (time ignored).
  final DateTime dateLimite;
  final double? montant;
  final String resume;
  final bool aVerifier;
  final bool fait;

  /// 'claude', 'regle' or 'manuel'.
  final String source;

  /// Stored at noon UTC so the day is the same in every time zone.
  static Timestamp jourVersTimestamp(DateTime d) => Timestamp.fromDate(DateTime.utc(d.year, d.month, d.day, 12));

  static DateTime timestampVersJour(Timestamp t) {
    final utc = t.toDate().toUtc();
    return DateTime(utc.year, utc.month, utc.day);
  }

  /// The document for a create. `creeLe` is set by the server, as the rules require.
  Map<String, Object?> versFirestore() => {
    'organisme': organisme,
    'organismeNom': organismeNom,
    'action': action,
    'titre': titre,
    'dateLimite': jourVersTimestamp(dateLimite),
    'montant': montant,
    'resume': resume,
    'aVerifier': aVerifier,
    'fait': false,
    'source': source,
    'creeLe': FieldValue.serverTimestamp(),
  };

  factory Echeance.depuisFirestore(String id, Map<String, dynamic> d) => Echeance(
    id: id,
    organisme: d['organisme'] as String,
    organismeNom: d['organismeNom'] as String,
    action: d['action'] as String,
    titre: d['titre'] as String,
    dateLimite: timestampVersJour(d['dateLimite'] as Timestamp),
    montant: (d['montant'] as num?)?.toDouble(),
    resume: d['resume'] as String,
    aVerifier: d['aVerifier'] as bool,
    fait: d['fait'] as bool,
    source: d['source'] as String,
  );

  Echeance copier({String? titre, DateTime? dateLimite, double? montant, bool effacerMontant = false}) => Echeance(
    id: id,
    organisme: organisme,
    organismeNom: organismeNom,
    action: action,
    titre: titre ?? this.titre,
    dateLimite: dateLimite ?? this.dateLimite,
    montant: effacerMontant ? null : (montant ?? this.montant),
    resume: resume,
    aVerifier: aVerifier,
    fait: fait,
    source: source,
  );
}
