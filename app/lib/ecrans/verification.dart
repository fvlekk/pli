import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../modeles/echeance.dart';
import '../modeles/lecture.dart';
import '../modeles/libelles.dart';
import '../outils/dates.dart';
import '../services/depot_echeances.dart';
import '../theme.dart';
import '../widgets/cachet.dart';

/// The user checks what was read before anything is saved. This screen is the verification step.
class EcranVerification extends StatefulWidget {
  const EcranVerification({super.key, required this.lecture, required this.depot, required this.maintenant});

  final Lecture lecture;
  final DepotEcheances depot;
  final DateTime Function() maintenant;

  @override
  State<EcranVerification> createState() => _EcranVerificationState();
}

class _EcranVerificationState extends State<EcranVerification> {
  late final _titre = TextEditingController(text: widget.lecture.titre);
  late final _montant = TextEditingController(
    text: widget.lecture.montant == null ? '' : euros(widget.lecture.montant!).replaceAll(RegExp(r'[^\d,]'), ''),
  );
  late DateTime? _date = widget.lecture.dateLimite;
  // Only a pure information letter skips the form; a missing date must be asked, never dropped.
  late bool _rappelQuandMeme = widget.lecture.action != 'aucune';
  bool _corrige = false;
  bool _enregistrement = false;
  String? _erreurMontant;

  Lecture get _l => widget.lecture;

  @override
  void dispose() {
    _titre.dispose();
    _montant.dispose();
    super.dispose();
  }

  Future<void> _choisirDate() async {
    final aujourdhui = widget.maintenant();
    final premier = DateTime(aujourdhui.year - 1);
    final dernier = DateTime(aujourdhui.year + 5, 12, 31);
    // A date read far in the past or future must not crash the picker: start it within its range.
    var initiale = _date ?? aujourdhui.add(const Duration(days: 7));
    if (initiale.isBefore(premier)) initiale = premier;
    if (initiale.isAfter(dernier)) initiale = dernier;
    final choisie = await showDatePicker(
      context: context,
      initialDate: initiale,
      firstDate: premier,
      lastDate: dernier,
      helpText: 'Avant le',
    );
    if (choisie != null) {
      setState(() {
        _date = choisie;
        _corrige = true;
      });
    }
  }

  double? _lireMontant() {
    final brut = _montant.text.replaceAll(RegExp(r'[\s€]'), '').replaceAll(',', '.');
    if (brut.isEmpty) return null;
    final valeur = double.tryParse(brut);
    return valeur != null && valeur >= 0 && valeur < 1000000 ? valeur : double.nan;
  }

  Future<void> _enregistrer() async {
    final montant = _lireMontant();
    if (montant != null && montant.isNaN) {
      setState(() => _erreurMontant = 'Écris un montant comme 90 ou 87,42');
      return;
    }
    setState(() {
      _erreurMontant = null;
      _enregistrement = true;
    });
    final echeance = Echeance(
      organisme: _l.organisme,
      organismeNom: _borne(_l.organismeNom, 120),
      action: _l.action,
      titre: _borne(_titre.text.trim(), 120),
      dateLimite: _date!,
      montant: montant,
      resume: _borne(_l.resume, 500),
      // A date or an amount the user set themselves is verified by definition.
      aVerifier: _l.aVerifier && !_corrige && montant == _l.montant,
      fait: false,
      source: _l.source == 'claude' ? 'claude' : 'regle',
    );
    try {
      await widget.depot.ajouter(echeance);
      if (mounted) Navigator.of(context).pop(true);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() => _enregistrement = false);
      final message = e.code == 'permission-denied'
          ? 'Cette échéance n\'a pas pu être enregistrée : un champ n\'est pas valide. Corrige-le et réessaie.'
          : 'Enregistrement impossible. Vérifie ta connexion et réessaie.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// Same limits as firestore.rules.
  static String _borne(String texte, int max) => texte.length <= max ? texte : texte.substring(0, max);

  @override
  Widget build(BuildContext context) {
    final jours = _date == null ? null : joursRestants(_date!, widget.maintenant());
    final rebours = jours == null ? (nombre: '?', unite: 'date à choisir') : compteARebours(jours);
    final peutEnregistrer = _date != null && _titre.text.trim().isNotEmpty && !_enregistrement;

    return Scaffold(
      appBar: AppBar(title: const Text('Vérifie avant d\'enregistrer')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Espaces.m),
          children: [
            CoupDeTampon(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Cachet(
                  nombre: rebours.nombre,
                  unite: rebours.unite,
                  couleur: jours != null && estUrgent(jours) ? Couleurs.cire : Couleurs.tampon,
                  haut: _date == null ? 'à dater' : DateFormatCachet.date(_date!),
                  bas: libelleOrganisme(_l.organisme),
                  taille: 150,
                  ondes: true,
                  semantique: jours == null ? 'Pas de date trouvée' : '${rebours.nombre} ${rebours.unite}',
                ),
              ),
            ),
            const SizedBox(height: Espaces.l),
            if (_l.aVerifier) ...[_AVerifier(raison: _l.raisonVerification), const SizedBox(height: Espaces.m)],
            if (!_rappelQuandMeme) ..._rienAFaire() else ..._formulaire(),
          ],
        ),
      ),
      bottomNavigationBar: _rappelQuandMeme
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(Espaces.m, Espaces.s, Espaces.m, Espaces.m),
              child: FilledButton(
                onPressed: peutEnregistrer ? _enregistrer : null,
                child: Text(_date == null ? 'Choisis une date pour enregistrer' : 'Enregistrer l\'échéance'),
              ),
            )
          : null,
    );
  }

  List<Widget> _rienAFaire() => [
    const Text('Rien à faire avec ce courrier', style: Textes.titre),
    const SizedBox(height: Espaces.s),
    Text(_l.resume, style: Textes.corps),
    const SizedBox(height: Espaces.l),
    FilledButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Compris')),
    const SizedBox(height: Espaces.s),
    OutlinedButton(
      onPressed: () => setState(() => _rappelQuandMeme = true),
      child: const Text('Créer un rappel quand même'),
    ),
  ];

  List<Widget> _formulaire() => [
    TextField(
      controller: _titre,
      maxLength: 120,
      style: Textes.ligne,
      decoration: const InputDecoration(labelText: 'Ce qu\'il faut faire', counterText: ''),
      onChanged: (_) => setState(() {}),
    ),
    const SizedBox(height: Espaces.s),
    Text('De la part de', style: Textes.discret),
    Text(_l.organismeNom, style: Textes.corps),
    const SizedBox(height: Espaces.m),
    InkWell(
      onTap: _choisirDate,
      borderRadius: BorderRadius.circular(6),
      child: InputDecorator(
        decoration: const InputDecoration(labelText: 'Avant le', suffixIcon: Icon(Icons.event_outlined)),
        child: Text(_date == null ? 'Choisir une date' : dateLongue(_date!), style: Textes.corps),
      ),
    ),
    const SizedBox(height: Espaces.m),
    TextField(
      controller: _montant,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: 'Montant (facultatif)', suffixText: '€', errorText: _erreurMontant),
    ),
    const SizedBox(height: Espaces.m),
    Text(_l.resume, style: Textes.corps.copyWith(color: Couleurs.encreDouce)),
    const SizedBox(height: Espaces.m),
    Text(
      _l.source == 'claude' ? 'Lu par Claude. Vérifie la date et le montant.' : 'Lu par la règle simple, sans IA.',
      style: Textes.discret,
    ),
  ];
}

class _AVerifier extends StatelessWidget {
  const _AVerifier({required this.raison});

  final String? raison;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Espaces.m),
      decoration: const BoxDecoration(
        color: Couleurs.feuille,
        border: Border(left: BorderSide(color: Couleurs.cire, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('À vérifier', style: Textes.ligne.copyWith(color: Couleurs.cire)),
          const SizedBox(height: Espaces.xs),
          Text(_phrase(raison), style: Textes.corps),
        ],
      ),
    );
  }

  static String _phrase(String? raison) {
    if (raison == null || raison.isEmpty) return 'Relis le courrier : une valeur est incertaine.';
    return '${raison[0].toUpperCase()}${raison.substring(1)}.';
  }
}

/// "18 oct. 2026" for the postmark's top arc.
abstract final class DateFormatCachet {
  static String date(DateTime d) => '${dateCourte(d)} ${d.year}';
}
