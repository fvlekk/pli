import 'package:flutter/material.dart';

import '../theme.dart';

/// Success: the mint of the « Fait » pill. Alert: the coral of urgent pills.
enum TonNotification { succes, alerte }

/// A Buddy-style notice: a small white card with a round pill and a line saying what happened, instead of the
/// default dark Material bar. `detail` says what exactly (« Payer la facture · avant le 12 nov. »).
void notifier(
  ScaffoldMessengerState messager,
  String titre, {
  String? detail,
  TonNotification ton = TonNotification.succes,
  SnackBarAction? action,
  Duration duree = const Duration(seconds: 4),
}) {
  messager
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: _Notification(titre: titre, detail: detail, ton: ton),
        action: action,
        duration: duree,
      ),
    );
}

class _Notification extends StatelessWidget {
  const _Notification({required this.titre, required this.detail, required this.ton});

  final String titre;
  final String? detail;
  final TonNotification ton;

  @override
  Widget build(BuildContext context) {
    final (icone, couleur, fond) = switch (ton) {
      TonNotification.succes => (Icons.check_rounded, Couleurs.menthe, Couleurs.mentheFond),
      TonNotification.alerte => (Icons.priority_high_rounded, Couleurs.rouge, Couleurs.corailPale),
    };
    return Row(
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
      ],
    );
  }
}
