import 'package:flutter/material.dart';

import '../theme.dart';
import 'carte_cliquable.dart';

/// An option as a Buddy-style card: an emoji in a soft circle, a title and a hint.
class Choix extends StatelessWidget {
  const Choix({super.key, required this.emoji, required this.titre, required this.detail, required this.onTap});

  final String emoji;
  final String titre;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CarteCliquable(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: Couleurs.corailPale, shape: BoxShape.circle),
            child: Text(emoji, style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: Espaces.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titre, style: Textes.ligne),
                Text(detail, style: Textes.discret),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Couleurs.encreDouce),
        ],
      ),
    );
  }
}
