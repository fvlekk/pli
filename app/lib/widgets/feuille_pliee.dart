import 'package:flutter/material.dart';

import '../theme.dart';

/// A letter folded in three: each panel is a time horizon, separated by a real-looking crease.
class FeuillePliee extends StatelessWidget {
  const FeuillePliee({super.key, required this.volets});

  final List<Widget> volets;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Couleurs.feuille,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Couleurs.pli),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < volets.length; i++) ...[if (i > 0) const Pli(), volets[i]],
        ],
      ),
    );
  }
}

/// The crease: shade above the fold line, light below, like paper that was folded and opened again.
class Pli extends StatelessWidget {
  const Pli({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 14,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Couleurs.feuille, Color(0xFFEDF1F5), Color(0xFFDCE3EA), Color(0xFFF6F8FA), Couleurs.feuille],
          stops: [0, 0.42, 0.5, 0.58, 1],
        ),
      ),
    );
  }
}

class Volet extends StatelessWidget {
  const Volet({super.key, required this.titre, required this.enfants, this.couleurTitre = Couleurs.encre});

  final String titre;
  final List<Widget> enfants;
  final Color couleurTitre;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Espaces.m, bottom: Espaces.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Espaces.m),
            child: Semantics(
              header: true,
              child: Text(titre, style: Textes.volet.copyWith(color: couleurTitre)),
            ),
          ),
          ...enfants,
        ],
      ),
    );
  }
}
