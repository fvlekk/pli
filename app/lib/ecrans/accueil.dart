import 'package:flutter/material.dart';

import '../modeles/echeance.dart';
import '../modeles/libelles.dart';
import '../outils/dates.dart';
import '../services/depot_echeances.dart';
import '../services/lecteur_courrier.dart';
import '../services/session.dart';
import '../theme.dart';
import '../widgets/carte_cliquable.dart';
import '../widgets/carte_echeance.dart';
import '../widgets/notification.dart';
import 'ajout.dart';

class EcranAccueil extends StatelessWidget {
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

  Future<void> _ajouter(BuildContext context) async {
    final enregistree = await Navigator.of(context).push<Echeance>(
      MaterialPageRoute(
        builder: (_) => EcranAjout(depot: depot, lecteur: lecteur, maintenant: maintenant),
      ),
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
          stream: depot.surveiller(),
          builder: (context, instantane) {
            if (instantane.hasError) {
              return _Message(
                texte: 'Impossible de charger tes échéances. Vérifie ta connexion, elles reviendront toutes seules.',
              );
            }
            if (!instantane.hasData) return const Center(child: CircularProgressIndicator());
            return _Contenu(
              echeances: instantane.data!,
              aujourdhui: maintenant(),
              depot: depot,
              compte: compte,
              onCompteChange: onCompteChange,
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
        const Text('pli', style: Textes.marque),
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
        if (compte case final compte?) ...[
          const SizedBox(height: Espaces.l),
          _CarteCompte(compte: compte, listeVide: echeances.isEmpty, onCompteChange: onCompteChange),
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
    await depot.marquerFait(echeance.id!, fait);
    notifier(
      messager,
      fait ? 'Marqué comme fait' : 'Remis à faire',
      detail: echeance.titre,
      action: SnackBarAction(label: 'Annuler', onPressed: () => depot.marquerFait(echeance.id!, !fait)),
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
            Text(echeance.organismeNom, style: Textes.discret),
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

/// Anonymous until the user asks: then the list is kept with their Google account, to find it on another phone.
class _CarteCompte extends StatefulWidget {
  const _CarteCompte({required this.compte, required this.listeVide, this.onCompteChange});

  final Compte compte;
  final bool listeVide;
  final VoidCallback? onCompteChange;

  @override
  State<_CarteCompte> createState() => _CarteCompteState();
}

class _CarteCompteState extends State<_CarteCompte> {
  bool _enCours = false;

  Future<void> _garder() async {
    final messager = ScaffoldMessenger.of(context);
    setState(() => _enCours = true);
    try {
      switch (await widget.compte.garderAvecGoogle(listeVide: widget.listeVide)) {
        case ResultatGoogle.relie:
          notifier(messager, 'Échéances gardées avec Google', detail: 'Tu les retrouveras sur un autre téléphone.');
        case ResultatGoogle.connecte:
          widget.onCompteChange?.call();
        case ResultatGoogle.annule:
          break;
      }
    } on CompteImpossible catch (e) {
      notifier(
        messager,
        'Connexion Google impossible',
        detail: e.message,
        ton: TonNotification.alerte,
        duree: const Duration(seconds: 8),
      );
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.compte.estAnonyme) {
      final email = widget.compte.email;
      return Text(
        email == null ? 'Échéances gardées avec ton compte Google.' : 'Échéances gardées avec $email.',
        style: Textes.discret,
        textAlign: TextAlign.center,
      );
    }
    return CarteCliquable(
      onTap: _enCours ? () {} : _garder,
      child: Row(
        children: [
          const Text('🔐', style: TextStyle(fontSize: 22)),
          const SizedBox(width: Espaces.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.listeVide ? 'Retrouver mes échéances avec Google' : 'Garder mes échéances avec Google',
                  style: Textes.ligne,
                ),
                Text(
                  widget.listeVide
                      ? 'Si tu les as gardées sur un autre téléphone.'
                      : 'Pour les retrouver sur un autre téléphone.',
                  style: Textes.discret,
                ),
              ],
            ),
          ),
          if (_enCours)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          else
            const Icon(Icons.chevron_right, color: Couleurs.encreDouce),
        ],
      ),
    );
  }
}
