/// What the backend read in a letter (POST /v1/extractions). Mirrors backend/src/pli/schema.py.
class Lecture {
  const Lecture({
    required this.organisme,
    required this.organismeNom,
    required this.action,
    required this.titre,
    required this.dateLimite,
    required this.montant,
    required this.resume,
    required this.aVerifier,
    required this.raisonVerification,
    required this.source,
    required this.modele,
  });

  final String organisme;
  final String organismeNom;
  final String action;
  final String titre;
  final DateTime? dateLimite;
  final double? montant;
  final String resume;
  final bool aVerifier;
  final String? raisonVerification;
  final String source;
  final String? modele;

  bool get aUneEcheance => action != 'aucune' && dateLimite != null;

  factory Lecture.depuisJson(Map<String, dynamic> json) {
    final e = json['extraction'] as Map<String, dynamic>;
    final date = e['date_limite'] as String?;
    return Lecture(
      organisme: e['organisme'] as String,
      organismeNom: e['organisme_nom'] as String,
      action: e['action'] as String,
      titre: e['titre'] as String,
      dateLimite: date == null ? null : DateTime.parse(date),
      montant: (e['montant'] as num?)?.toDouble(),
      resume: e['resume'] as String,
      aVerifier: e['a_verifier'] as bool,
      raisonVerification: e['raison_verification'] as String?,
      source: json['source'] as String,
      modele: json['modele'] as String?,
    );
  }
}
