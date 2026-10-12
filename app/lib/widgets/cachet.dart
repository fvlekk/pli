import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// The postmark: days left in the middle, the date on the top arc, the organisation on the bottom arc and,
/// at large sizes, the wavy cancellation lines of a French postmark. Pli's signature element.
class Cachet extends StatelessWidget {
  const Cachet({
    super.key,
    required this.nombre,
    required this.unite,
    required this.couleur,
    this.haut,
    this.bas,
    this.taille = 64,
    this.ondes = false,
    this.inclinaison = -0.12,
    required this.semantique,
  });

  final String nombre;
  final String unite;
  final Color couleur;

  /// Text on the top arc (the date) and on the bottom arc (the organisation). Drawn from 100 px up.
  final String? haut;
  final String? bas;
  final double taille;
  final bool ondes;

  /// Radians. A slight, item-specific tilt so a list does not look machine-stamped.
  final double inclinaison;
  final String semantique;

  /// A stable tilt between -0.18 and 0.08 rad derived from an id.
  static double inclinaisonPour(String? id) {
    final h = (id ?? '').codeUnits.fold<int>(7, (a, c) => (a * 31 + c) & 0xffff);
    return -0.18 + (h % 100) / 100 * 0.26;
  }

  @override
  Widget build(BuildContext context) {
    final largeur = ondes ? taille * 2.1 : taille;
    return Semantics(
      label: semantique,
      excludeSemantics: true,
      child: CustomPaint(
        size: Size(largeur, taille),
        painter: _PeintreCachet(
          nombre: nombre,
          unite: unite,
          couleur: couleur,
          haut: taille >= 100 ? haut : null,
          bas: taille >= 100 ? bas : null,
          ondes: ondes,
          inclinaison: inclinaison,
        ),
      ),
    );
  }
}

class _PeintreCachet extends CustomPainter {
  _PeintreCachet({
    required this.nombre,
    required this.unite,
    required this.couleur,
    required this.haut,
    required this.bas,
    required this.ondes,
    required this.inclinaison,
  });

  final String nombre;
  final String unite;
  final Color couleur;
  final String? haut;
  final String? bas;
  final bool ondes;
  final double inclinaison;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.height;
    final centre = Offset(s / 2, s / 2);
    final encre = couleur.withValues(alpha: 0.92);
    final rayon = s / 2 - s * 0.03;

    if (ondes) _ondes(canvas, size, centre, rayon, encre);

    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(inclinaison);

    final trait = Paint()
      ..style = PaintingStyle.stroke
      ..color = encre;
    canvas.drawCircle(Offset.zero, rayon, trait..strokeWidth = s * 0.04);
    final avecArcs = haut != null || bas != null;
    if (avecArcs) canvas.drawCircle(Offset.zero, rayon * 0.7, trait..strokeWidth = s * 0.014);

    final tailleNombre = s * (avecArcs ? 0.27 : (nombre.length > 2 ? 0.3 : 0.36));
    final pNombre = _texte(nombre, Polices.titre, tailleNombre, encre);
    final pUnite = _texte(unite, Polices.texte, s * (avecArcs ? 0.075 : 0.14), encre, poids: FontWeight.w700);
    final hauteur = pNombre.height * 0.86 + pUnite.height;
    pNombre.paint(canvas, Offset(-pNombre.width / 2, -hauteur / 2));
    pUnite.paint(canvas, Offset(-pUnite.width / 2, -hauteur / 2 + pNombre.height * 0.86));

    final rayonArc = rayon * 0.85;
    if (haut != null) _arc(canvas, haut!, rayonArc, s * 0.078, encre, enHaut: true);
    if (bas != null) _arc(canvas, bas!, rayonArc, s * 0.078, encre, enHaut: false);
    canvas.restore();
  }

  void _ondes(Canvas canvas, Size size, Offset centre, double rayon, Color encre) {
    final s = size.height;
    final trait = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.022
      ..strokeCap = StrokeCap.round
      ..color = encre;
    final debut = centre.dx + rayon + s * 0.06;
    const lignes = 5;
    final ecart = s * 0.11;
    for (var i = 0; i < lignes; i++) {
      final y = centre.dy + (i - (lignes - 1) / 2) * ecart;
      final chemin = Path()..moveTo(debut, y);
      for (var x = debut; x <= size.width - s * 0.02; x += 1) {
        chemin.lineTo(x, y + math.sin((x - debut) / (s * 0.3) * 2 * math.pi) * s * 0.035);
      }
      canvas.drawPath(chemin, trait);
    }
  }

  /// Letters along an arc, reading left to right on top and on the bottom.
  void _arc(Canvas canvas, String texte, double rayon, double taille, Color encre, {required bool enHaut}) {
    final lettres = [for (final c in texte.characters) _texte(c, Polices.texte, taille, encre, poids: FontWeight.w700)];
    const espacement = 1.12;
    final total = lettres.fold<double>(0, (a, p) => a + p.width * espacement) / rayon;
    var angle = enHaut ? -math.pi / 2 - total / 2 : math.pi / 2 + total / 2;
    for (final p in lettres) {
      final demi = p.width * espacement / 2 / rayon;
      angle += enHaut ? demi : -demi;
      canvas.save();
      canvas.rotate(angle + (enHaut ? math.pi / 2 : -math.pi / 2));
      final y = enHaut ? -rayon - p.height / 2 : rayon - p.height / 2;
      p.paint(canvas, Offset(-p.width / 2, y));
      canvas.restore();
      angle += enHaut ? demi : -demi;
    }
  }

  TextPainter _texte(String t, String famille, double taille, Color c, {FontWeight poids = FontWeight.w400}) {
    return TextPainter(
      text: TextSpan(
        text: t,
        style: TextStyle(fontFamily: famille, fontSize: taille, color: c, fontWeight: poids, height: 1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  @override
  bool shouldRepaint(_PeintreCachet old) =>
      old.nombre != nombre ||
      old.unite != unite ||
      old.couleur != couleur ||
      old.haut != haut ||
      old.bas != bas ||
      old.inclinaison != inclinaison;
}

/// The one orchestrated motion in the app: the postmark lands like a stamp when a letter has been read.
class CoupDeTampon extends StatefulWidget {
  const CoupDeTampon({super.key, required this.child});

  final Widget child;

  @override
  State<CoupDeTampon> createState() => _CoupDeTamponState();
}

class _CoupDeTamponState extends State<CoupDeTampon> with SingleTickerProviderStateMixin {
  late final _controleur = AnimationController(vsync: this, duration: const Duration(milliseconds: 460));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controleur.value = 1;
    } else if (!_controleur.isAnimating && _controleur.value == 0) {
      _controleur.forward();
    }
  }

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final descente = CurvedAnimation(
      parent: _controleur,
      curve: const Interval(0, 0.55, curve: Curves.easeInCubic),
    );
    final rebond = CurvedAnimation(
      parent: _controleur,
      curve: const Interval(0.55, 1, curve: Curves.easeOutBack),
    );
    return AnimatedBuilder(
      animation: _controleur,
      builder: (context, enfant) {
        final echelle = _controleur.value < 0.55 ? 1.6 - 0.62 * descente.value : 0.98 + 0.02 * rebond.value;
        return Opacity(
          opacity: (descente.value * 1.4).clamp(0, 1),
          child: Transform.scale(scale: echelle, child: enfant),
        );
      },
      child: widget.child,
    );
  }
}
