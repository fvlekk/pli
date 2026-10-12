import 'package:flutter/material.dart';

import '../modeles/echeance.dart';
import '../modeles/libelles.dart';
import '../outils/dates.dart';
import '../services/depot_echeances.dart';
import '../services/lecteur_courrier.dart';
import '../theme.dart';
import '../widgets/cachet.dart';
import '../widgets/feuille_pliee.dart';
import '../widgets/ligne_echeance.dart';
import 'ajout.dart';

class EcranAccueil extends StatelessWidget {
  const EcranAccueil({super.key, required this.depot, required this.lecteur, required this.maintenant});

  final DepotEcheances depot;
  final LecteurCourrier lecteur;
  final DateTime Function() maintenant;

  Future<void> _ajouter(BuildContext context) async {
    final enregistree = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EcranAjout(depot: depot, lecteur: lecteur, maintenant: maintenant),
      ),
    );
    if (enregistree == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Échéance enregistrée')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<List<Echeance>>(
          stream: depot.surveiller(),
          builder: (context, instantane) {
            if (instantane.hasError) {
              return _Message(
                texte: 'Impossible de charger tes échéances. Vérifie ta connexion, elles reviendront toutes seules.',
              );
            }
            if (!instantane.hasData) return const Center(child: CircularProgressIndicator());
            return _Contenu(echeances: instantane.data!, aujourdhui: maintenant(), depot: depot);
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(Espaces.m, Espaces.s, Espaces.m, Espaces.m),
        child: FilledButton.icon(
          onPressed: () => _ajouter(context),
          icon: const Icon(Icons.add),
          label: const Text('Ajouter un courrier'),
        ),
      ),
    );
  }
}

class _Contenu extends StatelessWidget {
  const _Contenu({required this.echeances, required this.aujourdhui, required this.depot});

  final List<Echeance> echeances;
  final DateTime aujourdhui;
  final DepotEcheances depot;

  @override
  Widget build(BuildContext context) {
    final aFaire = echeances.where((e) => !e.fait).toList();
    final faites = echeances.where((e) => e.fait).toList();
    final parHorizon = <Horizon, List<Echeance>>{for (final h in Horizon.values) h: []};
    for (final e in aFaire) {
      parHorizon[horizonDe(joursRestants(e.dateLimite, aujourdhui))]!.add(e);
    }

    final volets = <Widget>[
      for (final (horizon, titre) in [
        (Horizon.enRetard, 'En retard'),
        (Horizon.cetteSemaine, 'Cette semaine'),
        (Horizon.ceMois, 'Ce mois-ci'),
        (Horizon.plusTard, 'Plus tard'),
      ])
        if (parHorizon[horizon]!.isNotEmpty)
          Volet(
            titre: titre,
            couleurTitre: horizon == Horizon.enRetard ? Couleurs.cire : Couleurs.encre,
            enfants: [for (final e in parHorizon[horizon]!) _ligne(context, e)],
          ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(Espaces.m, Espaces.l, Espaces.m, Espaces.l),
      children: [
        const Text('Pli', style: Textes.marque),
        if (volets.isNotEmpty) ...[
          const SizedBox(height: Espaces.xs),
          Text(_resume(parHorizon), style: Textes.corps.copyWith(color: Couleurs.encreDouce)),
        ],
        const SizedBox(height: Espaces.l),
        if (volets.isEmpty) const _Vide() else FeuillePliee(volets: volets),
        if (faites.isNotEmpty) ...[
          const SizedBox(height: Espaces.l),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('Fait (${faites.length})', style: Textes.volet),
              children: [for (final e in faites) _ligne(context, e)],
            ),
          ),
        ],
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

  Widget _ligne(BuildContext context, Echeance e) => LigneEcheance(
    echeance: e,
    aujourdhui: aujourdhui,
    onTap: () => showModalBottomSheet<void>(
      context: context,
      backgroundColor: Couleurs.feuille,
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
    await depot.marquerFait(echeance.id!, fait);
    messager.showSnackBar(
      SnackBar(
        content: Text(fait ? 'Marqué comme fait' : 'Remis à faire'),
        action: SnackBarAction(label: 'Annuler', onPressed: () => depot.marquerFait(echeance.id!, !fait)),
      ),
    );
  }

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
      Navigator.of(context).pop();
      await depot.supprimer(echeance.id!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Espaces.l, 0, Espaces.l, Espaces.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(echeance.titre, style: Textes.titre),
            const SizedBox(height: Espaces.s),
            Text('${libelleOrganisme(echeance.organisme)}, ${echeance.organismeNom}', style: Textes.discret),
            const SizedBox(height: Espaces.m),
            Text('Avant le ${dateLongue(echeance.dateLimite)}', style: Textes.corps),
            if (echeance.montant != null) Text('Montant : ${euros(echeance.montant!)}', style: Textes.corps),
            const SizedBox(height: Espaces.s),
            Text(echeance.resume, style: Textes.corps.copyWith(color: Couleurs.encreDouce)),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Espaces.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Cachet(
            nombre: '0',
            unite: 'en attente',
            couleur: Couleurs.tampon,
            haut: 'rien à faire',
            bas: 'pli',
            taille: 150,
            ondes: true,
            semantique: 'Aucune échéance en attente',
          ),
          const SizedBox(height: Espaces.l),
          const Text('Aucun courrier en attente', style: Textes.titre),
          const SizedBox(height: Espaces.s),
          const Text(
            'Ajoute le prochain dès qu\'il arrive : Pli te dit quoi faire, et avant quand.',
            style: Textes.corps,
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
