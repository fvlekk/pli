import 'dart:async';

import 'package:flutter/material.dart';

import '../modeles/echeance.dart';
import '../modeles/libelles.dart';
import '../outils/dates.dart';
import '../services/depot_echeances.dart';
import '../services/lecteur_courrier.dart';
import '../services/session.dart';
import '../theme.dart';
import '../widgets/carte_echeance.dart';
import '../widgets/notification.dart';
import 'ajout.dart';
import 'feuille_compte.dart';

class EcranAccueil extends StatefulWidget {
  const EcranAccueil({
    super.key,
    required this.depot,
    required this.lecteur,
    required this.maintenant,
    this.compte,
    this.onCompteChange,
  });

  final DepotEcheances depot;
  final LecteurCourrier lecteur;
  final DateTime Function() maintenant;
  final Compte? compte;
  final VoidCallback? onCompteChange;

  @override
  State<EcranAccueil> createState() => _EcranAccueilState();
}

class _EcranAccueilState extends State<EcranAccueil> {
  late Stream<List<Echeance>> _echeances;
  late final AppLifecycleListener _retour;

  @override
  void initState() {
    super.initState();
    _echeances = widget.depot.surveiller();
    // A phone keeps the app alive for days: back in front, « Demain » must not still be yesterday's count.
    _retour = AppLifecycleListener(onResume: () => setState(() {}));
  }

  @override
  void didUpdateWidget(EcranAccueil ancien) {
    super.didUpdateWidget(ancien);
    // Another account's list was opened: the app restarts with a new depot, on this same screen.
    if (widget.depot != ancien.depot) _echeances = widget.depot.surveiller();
  }

  @override
  void dispose() {
    _retour.dispose();
    super.dispose();
  }

  Future<void> _ajouter(BuildContext context) async {
    final enregistree = await ouvrirAjout(
      context,
      depot: widget.depot,
      lecteur: widget.lecteur,
      maintenant: widget.maintenant,
    );
    if (enregistree != null && context.mounted) {
      notifier(
        ScaffoldMessenger.of(context),
        'Échéance enregistrée',
        // No-break spaces: « avant le 11 nov. » never splits across two lines.
        detail:
            '${enregistree.titre} · avant\u00a0le\u00a0${dateCourte(enregistree.dateLimite).replaceAll(' ', '\u00a0')}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<List<Echeance>>(
          // Its own state per account: the previous list must not stand in for one that has not answered yet.
          key: ObjectKey(widget.depot),
          stream: _echeances,
          builder: (context, instantane) {
            if (instantane.hasError) {
              // Firestore ends a listener on error (no network only delays it): nothing comes back by itself.
              return _Message(texte: 'Impossible de charger tes échéances. Ferme et rouvre Pli pour réessayer.');
            }
            if (!instantane.hasData) return const _Chargement();
            return _Contenu(
              echeances: instantane.data!,
              aujourdhui: widget.maintenant(),
              depot: widget.depot,
              compte: widget.compte,
              onCompteChange: widget.onCompteChange,
            );
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(Espaces.l, Espaces.s, Espaces.l, Espaces.m),
        child: FilledButton.icon(
          onPressed: () => _ajouter(context),
          icon: const Icon(Icons.add),
          label: const Text('Ajouter un courrier'),
        ),
      ),
    );
  }
}

class _Chargement extends StatelessWidget {
  const _Chargement();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: Espaces.m),
        Text('Chargement… Vérifie ta connexion si ça dure.', style: Textes.discret, textAlign: TextAlign.center),
      ],
    ),
  );
}

class _Contenu extends StatelessWidget {
  const _Contenu({
    required this.echeances,
    required this.aujourdhui,
    required this.depot,
    this.compte,
    this.onCompteChange,
  });

  final List<Echeance> echeances;
  final DateTime aujourdhui;
  final DepotEcheances depot;
  final Compte? compte;
  final VoidCallback? onCompteChange;

  @override
  Widget build(BuildContext context) {
    final aFaire = echeances.where((e) => !e.fait).toList()..sort((a, b) => a.dateLimite.compareTo(b.dateLimite));
    final faites = echeances.where((e) => e.fait).toList();
    final parHorizon = <Horizon, List<Echeance>>{for (final h in Horizon.values) h: []};
    for (final e in aFaire) {
      parHorizon[horizonDe(joursRestants(e.dateLimite, aujourdhui))]!.add(e);
    }

    final sections = [
      (Horizon.enRetard, 'En retard'),
      (Horizon.cetteSemaine, 'Cette semaine'),
      (Horizon.ceMois, 'Ce mois-ci'),
      (Horizon.plusTard, 'Plus tard'),
    ].where((s) => parHorizon[s.$1]!.isNotEmpty).toList();
    // Sorted by date, so the very first one is what to do first.
    final premiere = sections.isEmpty ? null : parHorizon[sections.first.$1]!.first;

    return ListView(
      padding: const EdgeInsets.fromLTRB(Espaces.l, Espaces.m, Espaces.l, Espaces.l),
      children: [
        Row(
          children: [
            const Expanded(child: Text('pli', style: Textes.marque)),
            if (compte case final compte?) BoutonCompte(compte: compte, onCompteChange: onCompteChange),
          ],
        ),
        const SizedBox(height: Espaces.l),
        const Text('Tes échéances 📬', style: Textes.titre),
        if (sections.isNotEmpty) ...[
          const SizedBox(height: Espaces.xs),
          Text(_resume(parHorizon), style: Textes.corps.copyWith(color: Couleurs.encreDouce)),
        ],
        if (sections.isEmpty) const _Vide(),
        for (final (horizon, titre) in sections) ...[
          const SizedBox(height: Espaces.l),
          Semantics(
            header: true,
            child: Text(
              titre,
              style: Textes.section.copyWith(color: horizon == Horizon.enRetard ? Couleurs.rouge : null),
            ),
          ),
          const SizedBox(height: Espaces.m),
          for (final e in parHorizon[horizon]!) _carte(context, e, enAvant: identical(e, premiere)),
        ],
        if (faites.isNotEmpty)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('Fait (${faites.length})', style: Textes.section),
              children: [for (final e in faites) _carte(context, e)],
            ),
          ),
      ],
    );
  }

  String _resume(Map<Horizon, List<Echeance>> parHorizon) {
    final retard = parHorizon[Horizon.enRetard]!.length;
    final semaine = parHorizon[Horizon.cetteSemaine]!.length;
    if (retard > 0) return retard == 1 ? 'Une démarche est en retard.' : '$retard démarches sont en retard.';
    if (semaine == 0) return 'Rien d\'urgent cette semaine.';
    return semaine == 1 ? 'Une chose à faire cette semaine.' : '$semaine choses à faire cette semaine.';
  }

  Widget _carte(BuildContext context, Echeance e, {bool enAvant = false}) => CarteEcheance(
    echeance: e,
    aujourdhui: aujourdhui,
    enAvant: enAvant,
    onTap: () => showModalBottomSheet<void>(
      context: context,
      backgroundColor: Couleurs.fond,
      showDragHandle: true,
      builder: (_) => _Detail(echeance: e, depot: depot),
    ),
  );
}

class _Detail extends StatelessWidget {
  const _Detail({required this.echeance, required this.depot});

  final Echeance echeance;
  final DepotEcheances depot;

  Future<void> _marquer(BuildContext context, bool fait) async {
    final messager = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    try {
      await depot.marquerFait(echeance.id!, fait);
      notifier(
        messager,
        fait ? 'Marqué comme fait' : 'Remis à faire',
        detail: echeance.titre,
        action: (libelle: 'Annuler', onPressed: () => unawaited(_marquerSansAnnonce(messager, !fait))),
      );
    } catch (_) {
      _signalerEchec(messager);
    }
  }

  Future<void> _marquerSansAnnonce(ScaffoldMessengerState messager, bool fait) async {
    try {
      await depot.marquerFait(echeance.id!, fait);
    } catch (_) {
      _signalerEchec(messager);
    }
  }

  /// Firestore shows a change at once and takes it back if the server refuses: the user must know why.
  void _signalerEchec(ScaffoldMessengerState messager) => notifier(
    messager,
    'Modification impossible',
    detail: 'Elle n\'a pas été enregistrée. Vérifie ta connexion et réessaie.',
    ton: TonNotification.alerte,
  );

  Future<void> _supprimer(BuildContext context) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (dialogue) => AlertDialog(
        title: const Text('Supprimer cette échéance ?'),
        content: const Text('Elle disparaît de ta liste. Pli n\'a jamais enregistré le courrier lui-même.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogue, false), child: const Text('Garder')),
          TextButton(onPressed: () => Navigator.pop(dialogue, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (confirme == true && context.mounted) {
      final messager = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      try {
        await depot.supprimer(echeance.id!);
      } catch (_) {
        _signalerEchec(messager);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // The sheet is capped at 9/16 of the screen and a summary can be 500 characters: scroll rather than hide
    // the buttons on a small phone.
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Espaces.l, 0, Espaces.l, Espaces.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Pastille('${emojiOrganisme(echeance.organisme)} ${libelleOrganisme(echeance.organisme)}'),
            const SizedBox(height: Espaces.s),
            Text(echeance.titre, style: Textes.section),
            const SizedBox(height: Espaces.xs),
            if (echeance.source != 'manuel') Text(echeance.organismeNom, style: Textes.discret),
            const SizedBox(height: Espaces.m),
            Text('Avant le ${dateLongue(echeance.dateLimite)}', style: Textes.corps),
            if (echeance.montant != null) Text('Montant : ${euros(echeance.montant!)}', style: Textes.corps),
            if (echeance.resume.isNotEmpty) ...[
              const SizedBox(height: Espaces.s),
              Text(echeance.resume, style: Textes.corps.copyWith(color: Couleurs.encreDouce)),
            ],
            const SizedBox(height: Espaces.l),
            FilledButton(
              onPressed: () => _marquer(context, !echeance.fait),
              child: Text(echeance.fait ? 'Remettre à faire' : 'C\'est fait'),
            ),
            const SizedBox(height: Espaces.s),
            OutlinedButton(onPressed: () => _supprimer(context), child: const Text('Supprimer')),
          ],
        ),
      ),
    );
  }
}

class _Vide extends StatelessWidget {
  const _Vide();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: Espaces.l),
      padding: const EdgeInsets.all(Espaces.l),
      decoration: decorationCarte(fond: Couleurs.mentheFond, bord: Couleurs.mentheFond),
      child: const Row(
        children: [
          Text('🏆', style: TextStyle(fontSize: 32)),
          SizedBox(width: Espaces.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Aucun courrier en attente', style: Textes.ligne),
                SizedBox(height: Espaces.xs),
                Text(
                  'Ajoute le prochain dès qu\'il arrive : Pli te dit quoi faire, et avant quand.',
                  style: Textes.discret,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.texte});

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Espaces.l),
        child: Text(texte, style: Textes.corps, textAlign: TextAlign.center),
      ),
    );
  }
}
