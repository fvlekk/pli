import 'package:flutter/material.dart';

import '../theme.dart';

/// Success: the mint of the « Fait » pill. Alert: the coral of urgent pills.
enum TonNotification { succes, alerte }

/// A Buddy-style notice: a small white card with a round pill and a line saying what happened, instead of the
/// default dark Material bar. `detail` says what exactly (« Payer la facture · avant le 12 nov. »).
/// `persist: false`: with an action, a SnackBar would otherwise stay until it is dismissed.
void notifier(
  ScaffoldMessengerState messager,
  String titre, {
  String? detail,
  TonNotification ton = TonNotification.succes,
  ({String libelle, VoidCallback onPressed})? action,
  Duration duree = const Duration(seconds: 4),
}) {
  messager
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: _Notification(
          titre: titre,
          detail: detail,
          ton: ton,
          action: action,
          fermer: messager.hideCurrentSnackBar,
        ),
        duration: duree,
        persist: false,
        dismissDirection: DismissDirection.down,
        // The card below is the visible notice: it slides on its own, and past the bar's edges.
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(),
        clipBehavior: Clip.none,
      ),
    );
}

class _Notification extends StatelessWidget {
  const _Notification({
    required this.titre,
    required this.detail,
    required this.ton,
    required this.action,
    required this.fermer,
  });

  final String titre;
  final String? detail;
  final TonNotification ton;
  final ({String libelle, VoidCallback onPressed})? action;
  final VoidCallback fermer;

  @override
  Widget build(BuildContext context) {
    // The SnackBar's own animation: in from below, and back down when its time is up.
    final animation = context.findAncestorWidgetOfExactType<SnackBar>()?.animation;
    final carte = _carte();
    if (animation == null || MediaQuery.disableAnimationsOf(context)) return carte;
    return SlideTransition(
      position: Tween(
        begin: const Offset(0, 1.5),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: carte,
    );
  }

  Widget _carte() {
    final (icone, couleur, fond) = switch (ton) {
      TonNotification.succes => (Icons.check_rounded, Couleurs.menthe, Couleurs.mentheFond),
      TonNotification.alerte => (Icons.priority_high_rounded, Couleurs.rouge, Couleurs.corailPale),
    };
    return Container(
      padding: const EdgeInsets.all(Espaces.m),
      decoration: decorationCarte(),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: fond, shape: BoxShape.circle),
            child: Icon(icone, color: couleur, size: 22),
          ),
          const SizedBox(width: Espaces.m),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titre, style: Textes.ligne, maxLines: 2, overflow: TextOverflow.ellipsis),
                if (detail case final detail?)
                  Text(detail, style: Textes.discret, maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (action case final action?)
            TextButton(
              onPressed: () {
                fermer();
                action.onPressed();
              },
              child: Text(action.libelle),
            ),
        ],
      ),
    );
  }
}
