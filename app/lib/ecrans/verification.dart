import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../modeles/echeance.dart';
import '../modeles/lecture.dart';
import '../modeles/libelles.dart';
import '../outils/dates.dart';
import '../services/depot_echeances.dart';
import '../theme.dart';
import '../widgets/carte_echeance.dart';
import '../widgets/notification.dart';

/// Firestore only answers once the server has the write: without network it would never answer.
const attenteEnregistrement = Duration(seconds: 15);

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
  bool get _manuelle => _l.source == 'manuel';

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
    // « 1.234 » means 1 234 € to a French reader, not 1,23 €: refuse what is not plainly an amount.
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(brut)) return double.nan;
    final valeur = double.parse(brut);
    return valeur < 1000000 ? valeur : double.nan;
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
      organismeNom: bornerTexte(_l.organismeNom, longueurMaxTitre),
      action: _l.action,
      titre: bornerTexte(_titre.text.trim(), longueurMaxTitre),
      dateLimite: _date!,
      montant: montant,
      resume: bornerTexte(_l.resume, longueurMaxResume),
      // A date or an amount the user set themselves is verified by definition.
      aVerifier: _l.aVerifier && !_corrige && montant == _l.montant,
      fait: false,
      source: _manuelle ? 'manuel' : (_l.source == 'claude' ? 'claude' : 'regle'),
    );
    final ecriture = Future<void>.sync(() => widget.depot.ajouter(echeance));
    try {
      await ecriture.timeout(attenteEnregistrement);
      if (mounted) Navigator.of(context).pop(echeance);
    } on TimeoutException {
      // The write stays in Firestore's queue and leaves when the network returns: saving again would duplicate it.
      if (!mounted) return;
      _annoncerLaSuite(ecriture, echeance);
      await _expliquerLAttente();
      // Straight back to the list, without the result that would announce a success.
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() => _enregistrement = false);
      final message = e is FirebaseException && e.code == 'permission-denied'
          ? 'Cette échéance n\'a pas pu être enregistrée : un champ n\'est pas valide. Corrige-le et réessaie.'
          : 'Enregistrement impossible. Vérifie ta connexion et réessaie.';
      notifier(
        ScaffoldMessenger.of(context),
        'Enregistrement impossible',
        detail: message,
        ton: TonNotification.alerte,
      );
    }
  }

  /// On the web the queue dies with the page, so only the server's answer may read as saved.
  void _annoncerLaSuite(Future<void> ecriture, Echeance echeance) {
    final messager = ScaffoldMessenger.of(context);
    unawaited(
      ecriture.then<void>(
        (_) => notifier(messager, 'Échéance enregistrée', detail: echeance.titre),
        onError: (Object _) => notifier(
          messager,
          'Échéance non enregistrée',
          detail: '${echeance.titre} : ajoute-la de nouveau.',
          ton: TonNotification.alerte,
        ),
      ),
    );
  }

  Future<void> _expliquerLAttente() => showDialog<void>(
    context: context,
    builder: (dialogue) => AlertDialog(
      title: const Text('Pas encore enregistrée'),
      content: const Text(
        'Le réseau ne répond pas. Laisse Pli ouvert : ton échéance partira dès qu\'il revient. '
        'Si tu le fermes, vérifie en revenant qu\'elle est bien dans ta liste.',
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogue), child: const Text('OK'))],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final jours = _date == null ? null : joursRestants(_date!, widget.maintenant());
    final peutEnregistrer = _date != null && _titre.text.trim().isNotEmpty && !_enregistrement;

    // Leaving during a save would drop the write's outcome, and saving again would duplicate it.
    return PopScope(
      canPop: !_enregistrement,
      child: Scaffold(
        appBar: AppBar(title: Text(_manuelle ? 'Nouvelle échéance' : 'Vérifie avant d\'enregistrer')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(Espaces.m),
            children: [
              if (!_manuelle) ...[_EnTete(lecture: _l, date: _date, jours: jours), const SizedBox(height: Espaces.l)],
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
      ),
    );
  }

  List<Widget> _rienAFaire() => [
    const Text('Rien à faire avec ce courrier', style: Textes.titre),
    const SizedBox(height: Espaces.s),
    Text(_l.resume, style: Textes.corps),
    const SizedBox(height: Espaces.l),
    FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Compris')),
    const SizedBox(height: Espaces.s),
    OutlinedButton(
      onPressed: () => setState(() => _rappelQuandMeme = true),
      child: const Text('Créer un rappel quand même'),
    ),
  ];

  List<Widget> _formulaire() => [
    TextField(
      controller: _titre,
      maxLength: longueurMaxTitre,
      style: Textes.ligne,
      decoration: const InputDecoration(labelText: 'Ce qu\'il faut faire', counterText: ''),
      onChanged: (_) => setState(() {}),
    ),
    const SizedBox(height: Espaces.s),
    if (!_manuelle) ...[
      Text('De la part de', style: Textes.discret),
      Text(_l.organismeNom, style: Textes.corps),
      const SizedBox(height: Espaces.m),
    ],
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
    if (!_manuelle) ...[
      const SizedBox(height: Espaces.m),
      Text(_l.resume, style: Textes.corps.copyWith(color: Couleurs.encreDouce)),
      const SizedBox(height: Espaces.m),
      Text(
        _l.source == 'claude' ? 'Lu par Claude. Vérifie la date et le montant.' : 'Lu par la règle simple, sans IA.',
        style: Textes.discret,
      ),
    ],
  ];
}

class _AVerifier extends StatelessWidget {
  const _AVerifier({required this.raison});

  final String? raison;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Espaces.m),
      decoration: decorationCarte(fond: Couleurs.corailPale, bord: Couleurs.corailPale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('À vérifier', style: Textes.ligne.copyWith(color: Couleurs.rouge)),
          const SizedBox(height: Espaces.xs),
          Text(_phrase(raison), style: Textes.corps),
        ],
      ),
    );
  }

  static String _phrase(String? raison) {
    final texte = raison?.trim() ?? '';
    if (texte.isEmpty) return 'Relis le courrier : une valeur est incertaine.';
    final phrase = '${texte[0].toUpperCase()}${texte.substring(1)}';
    // The model often ends its reason with a period already: never print « retenu.. ».
    return RegExp(r'[.!?…]$').hasMatch(phrase) ? phrase : '$phrase.';
  }
}

/// The lilac card on top: who sent it, and how many days are left.
class _EnTete extends StatelessWidget {
  const _EnTete({required this.lecture, required this.date, required this.jours});

  final Lecture lecture;
  final DateTime? date;
  final int? jours;

  @override
  Widget build(BuildContext context) {
    final pourInfo = lecture.action == 'aucune' && date == null;
    return Container(
      padding: const EdgeInsets.all(Espaces.m),
      decoration: decorationCarte(fond: Couleurs.lilas, bord: Couleurs.lilasBord),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('CE QUE PLI A LU', style: Textes.surtitre),
          const SizedBox(height: Espaces.s),
          Row(
            children: [
              if (pourInfo)
                const Pastille('Pour info', couleur: Couleurs.menthe, fond: Couleurs.mentheFond)
              else
                PastilleRebours(jours: jours),
              const SizedBox(width: Espaces.s),
              Flexible(child: Pastille('${emojiOrganisme(lecture.organisme)} ${libelleOrganisme(lecture.organisme)}')),
            ],
          ),
          const SizedBox(height: Espaces.s),
          Text(
            date != null
                ? 'Avant le ${dateCourte(date!)} ${date!.year}'
                : (pourInfo ? lecture.organismeNom : 'Pas de date trouvée'),
            style: Textes.section,
          ),
        ],
      ),
    );
  }
}
