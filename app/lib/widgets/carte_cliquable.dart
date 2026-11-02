import 'package:flutter/material.dart';

import '../theme.dart';

/// A Buddy-style card that reacts to a tap. The card paints its own shadow: an Ink decoration would be
/// clipped to the Material's rectangle and leave grey square corners under it.
class CarteCliquable extends StatelessWidget {
  const CarteCliquable({super.key, required this.onTap, required this.child, this.decoration});

  final VoidCallback onTap;
  final Widget child;

  /// White card by default; `decorationCarte(fond: …, bord: …)` for the lilac highlight.
  final BoxDecoration? decoration;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Espaces.m),
      child: DecoratedBox(
        decoration: decoration ?? decorationCarte(),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(Rayons.carte),
            child: Padding(padding: const EdgeInsets.all(Espaces.m), child: child),
          ),
        ),
      ),
    );
  }
}
