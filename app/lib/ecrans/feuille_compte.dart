import 'dart:async';

import 'package:flutter/material.dart';

import '../services/session.dart';
import '../theme.dart';
import '../widgets/choix.dart';
import '../widgets/notification.dart';
import 'confidentialite.dart';

/// The account button of the home screen: the first letter of the address once connected, a silhouette before.
class BoutonCompte extends StatefulWidget {
  const BoutonCompte({super.key, required this.compte, this.onCompteChange});

  final Compte compte;
  final VoidCallback? onCompteChange;

  @override
  State<BoutonCompte> createState() => _BoutonCompteState();
}

class _BoutonCompteState extends State<BoutonCompte> {
  Future<void> _ouvrir() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Couleurs.fond,
      showDragHandle: true,
      builder: (_) => _FeuilleCompte(compte: widget.compte, onCompteChange: widget.onCompteChange),
    );
    // Linking keeps the same list and the same app: only this button changes.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.compte.email;
    final initiale = widget.compte.estAnonyme || email == null || email.isEmpty ? null : email[0].toUpperCase();
    return IconButton(
      tooltip: 'Mon compte',
      onPressed: _ouvrir,
      icon: CircleAvatar(
        radius: 18,
        backgroundColor: Couleurs.corailPale,
        foregroundColor: Couleurs.encre,
        child: initiale == null ? const Icon(Icons.person_outline, size: 22) : Text(initiale, style: Textes.ligne),
      ),
    );
  }
}

void _signalerEchecGoogle(ScaffoldMessengerState messager, String detail) => notifier(
  messager,
  'Connexion Google impossible',
  detail: detail,
  ton: TonNotification.alerte,
  duree: const Duration(seconds: 8),
);

/// Says « added » only once the server has them. A refusal asks the user: the deadlines exist nowhere else they can reach.
/// The app restarts in place, so the messenger and the navigator outlive the sheet.
Future<void> _suivreFusion(Compte compte, ScaffoldMessengerState messager, NavigatorState navigateur) async {
  notifier(
    messager,
    'Compte Google connecté',
    detail: 'Ajout des échéances de cet appareil. Garde Pli ouvert.',
    duree: const Duration(seconds: 30),
  );
  while (!await compte.finFusion()) {
    if (!navigateur.mounted) return;
    messager.hideCurrentSnackBar();
    final reessayer = await showDialog<bool>(
      context: navigateur.context,
      barrierDismissible: false,
      builder: (dialogue) => AlertDialog(
        title: const Text('Échéances non ajoutées'),
        content: const Text(
          'Celles de cet appareil n\'ont pas rejoint ta liste. Si tu abandonnes, elles seront perdues.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogue, false), child: const Text('Abandonner')),
          TextButton(onPressed: () => Navigator.pop(dialogue, true), child: const Text('Réessayer')),
        ],
      ),
    );
    if (reessayer != true) return;
    compte.relancerFusion();
  }
  notifier(messager, 'Échéances ajoutées à ta liste');
}

class _FeuilleCompte extends StatefulWidget {
  const _FeuilleCompte({required this.compte, this.onCompteChange});

  final Compte compte;
  final VoidCallback? onCompteChange;

  @override
  State<_FeuilleCompte> createState() => _FeuilleCompteState();
}

class _FeuilleCompteState extends State<_FeuilleCompte> {
  bool _enCours = false;

  /// The sheet can be closed during the Google window: whatever Google answers must still reach the app. Pops only this
  /// sheet: a sheet already closing is no longer the current route, and the pop would remove the list under it.
  Future<void> _google(Future<ResultatGoogle> Function() action) async {
    final messager = ScaffoldMessenger.of(context);
    final navigateur = Navigator.of(context);
    final route = ModalRoute.of(context)!;
    void fermer() {
      if (route.isCurrent) navigateur.pop();
    }

    setState(() => _enCours = true);
    try {
      final resultat = await action();
      fermer();
      switch (resultat) {
        case ResultatGoogle.relie:
          notifier(messager, 'Compte Google connecté');
        case ResultatGoogle.connecte:
          widget.onCompteChange?.call();
        case ResultatGoogle.fusionEnCours:
          widget.onCompteChange?.call();
          unawaited(_suivreFusion(widget.compte, messager, navigateur));
        case ResultatGoogle.annule:
          break;
      }
    } on CompteImpossible catch (e) {
      fermer();
      _signalerEchecGoogle(messager, e.message);
    } catch (_) {
      fermer();
      _signalerEchecGoogle(messager, 'Réessaie dans un instant.');
    }
  }

  Future<void> _deconnecter() async {
    final messager = ScaffoldMessenger.of(context);
    final navigateur = Navigator.of(context);
    final route = ModalRoute.of(context)!;
    setState(() => _enCours = true);
    try {
      await widget.compte.deconnecter();
      if (route.isCurrent) navigateur.pop();
      widget.onCompteChange?.call();
    } catch (_) {
      if (route.isCurrent) navigateur.pop();
      notifier(messager, 'Déconnexion impossible', detail: 'Réessaie dans un instant.', ton: TonNotification.alerte);
    }
  }

  /// Asks first: nothing can bring the list back. The app then restarts on a new, empty session.
  Future<void> _supprimer() async {
    final compte = widget.compte;
    final confirme = await showDialog<bool>(
      context: context,
      builder: (dialogue) => AlertDialog(
        title: const Text('Supprimer tes données ?'),
        content: Text(
          compte.estAnonyme
              ? 'Toutes tes échéances seront effacées, pour de bon.'
              : 'Toutes tes échéances et ton compte Pli seront effacés, pour de bon. Google va te demander de '
                    'confirmer ton compte.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogue, false), child: const Text('Annuler')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Couleurs.rouge),
            onPressed: () => Navigator.pop(dialogue, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirme != true || !mounted) return;
    final messager = ScaffoldMessenger.of(context);
    final navigateur = Navigator.of(context);
    final route = ModalRoute.of(context)!;
    void fermer() {
      if (route.isCurrent) navigateur.pop();
    }

    setState(() => _enCours = true);
    try {
      final fait = await compte.supprimerMesDonnees();
      fermer();
      if (!fait) return;
      notifier(messager, 'Tes données sont supprimées');
      widget.onCompteChange?.call();
    } on CompteImpossible catch (e) {
      fermer();
      notifier(
        messager,
        'Suppression impossible',
        detail: e.message,
        ton: TonNotification.alerte,
        duree: const Duration(seconds: 8),
      );
    } catch (_) {
      fermer();
      notifier(messager, 'Suppression impossible', detail: 'Réessaie dans un instant.', ton: TonNotification.alerte);
    }
  }

  @override
  Widget build(BuildContext context) {
    final compte = widget.compte;
    return SafeArea(
      child: AbsorbPointer(
        absorbing: _enCours,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Espaces.l, 0, Espaces.l, Espaces.m),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_enCours) ...[
                const LinearProgressIndicator(backgroundColor: Couleurs.corailPale),
                const SizedBox(height: Espaces.m),
              ],
              if (compte.estAnonyme) ...[
                const Text('Sans compte', style: Textes.section),
                const SizedBox(height: Espaces.xs),
                const Text('Tes échéances sont liées à cet appareil et peuvent disparaître.', style: Textes.discret),
                const SizedBox(height: Espaces.m),
                Choix(
                  emoji: '🔐',
                  titre: 'Continuer avec Google',
                  detail: 'Les échéances de cet appareil restent dans ta liste.',
                  onTap: () => _google(compte.connecterAvecGoogle),
                ),
              ] else ...[
                Text(compte.email ?? 'Compte Google', style: Textes.section),
                const SizedBox(height: Espaces.m),
                Choix(
                  emoji: '🔁',
                  titre: 'Changer de compte',
                  detail: 'Ta liste actuelle reste sur ce compte.',
                  onTap: () => _google(compte.changerDeCompte),
                ),
                Choix(
                  emoji: '👋',
                  titre: 'Se déconnecter',
                  detail: 'Ta liste reste sur ton compte Google.',
                  onTap: _deconnecter,
                ),
              ],
              Choix(
                emoji: '🔒',
                titre: 'Confidentialité',
                detail: 'Ce que Pli fait de tes courriers.',
                onTap: () =>
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const EcranConfidentialite())),
              ),
              Choix(
                emoji: '🗑️',
                titre: 'Supprimer mes données',
                detail: 'Tes échéances, pour de bon.',
                onTap: _supprimer,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
