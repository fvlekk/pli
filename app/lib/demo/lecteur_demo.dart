import '../exemples.dart';
import '../modeles/lecture.dart';
import '../services/lecteur_courrier.dart';

/// Reads the sample letters only, with the answers the Claude extractor gives on them (eval cases dev_04, dev_06
/// and dev_03). Anything else is refused: the demo has no backend.
class LecteurDemo implements LecteurCourrier {
  LecteurDemo({this.delai = const Duration(seconds: 1)});

  final Duration delai;

  final _lectures = {for (final e in exemples) e.texte.trim(): _parTitre[e.titre]!};

  @override
  Future<Lecture> lire(CourrierAEnvoyer courrier) async {
    final lecture = switch (courrier) {
      CourrierTexte(:final texte) => _lectures[texte.trim()],
      CourrierFichier() => null,
    };
    if (lecture == null) throw const LectureImpossible('Mode démo : essaie un des courriers d\'exemple.');
    await Future<void>.delayed(delai);
    return lecture;
  }
}

/// Keyed by the sample's title in exemples.dart.
final _parTitre = {
  'Une amende': Lecture(
    organisme: 'antai',
    organismeNom: 'Agence nationale de traitement automatisé des infractions',
    action: 'payer',
    titre: 'Payer l\'amende pour excès de vitesse',
    dateLimite: DateTime(2026, 10, 18),
    montant: 90,
    resume: 'Paie 90 € avant le 18 octobre pour le tarif minoré. Après, l\'amende passe à 135 €, puis à 375 €.',
    aVerifier: false,
    raisonVerification: null,
    source: 'claude',
    modele: 'claude-opus-5-5',
  ),
  'Une facture d\'électricité': Lecture(
    organisme: 'energie',
    organismeNom: 'Voltéa Énergie',
    action: 'payer',
    titre: 'Payer la facture d\'électricité',
    // « avant le 12/11 »: the last day to pay is the 11th.
    dateLimite: DateTime(2026, 11, 11),
    montant: 87.42,
    resume: 'Paie 87,42 € avant le 12 novembre, par carte sur ton espace client ou par virement.',
    aVerifier: false,
    raisonVerification: null,
    source: 'claude',
    modele: 'claude-opus-5-5',
  ),
  'Un renouvellement de droits': Lecture(
    organisme: 'assurance_maladie',
    organismeNom: 'Caisse primaire d\'assurance maladie de Seine-Saint-Denis',
    action: 'renouveler',
    titre: 'Renouveler la Complémentaire santé solidaire',
    dateLimite: DateTime(2026, 10, 31),
    montant: null,
    resume: 'Ton droit s\'arrête le 31 décembre. Refais ta demande sur ton compte ameli d\'ici le 31 octobre.',
    aVerifier: false,
    raisonVerification: null,
    source: 'claude',
    modele: 'claude-opus-5-5',
  ),
};
