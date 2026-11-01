import 'package:flutter/material.dart';

/// Design tokens. Widgets use these, never raw colors.
///
/// Style aligned on Buddy's app: white background, coral accent, Baloo 2, rounded white cards with a soft
/// shadow, pastel pills, and one lilac card for what matters most.
abstract final class Couleurs {
  static const fond = Color(0xFFFFFFFF);
  static const carte = Color(0xFFFFFFFF);

  /// Text.
  static const encre = Color(0xFF1B181D);

  /// Secondary text (7:1 on white).
  static const encreDouce = Color(0xFF55505A);

  /// Accent: primary actions, the wordmark, urgent dates.
  static const corail = Color(0xFFFF5151);
  static const corailPale = Color(0xFFFFE9E9);

  /// Darker red for small text (dates, "en retard"): readable on white (5.9:1).
  static const rouge = Color(0xFFD01F2E);

  /// The highlighted card ("à faire en premier").
  static const lilas = Color(0xFFFCF0FF);
  static const lilasBord = Color(0xFFE6CCF2);
  static const violet = Color(0xFF8A5BA6);

  /// Pills.
  static const mentheFond = Color(0xFFD5FBEB);
  static const menthe = Color(0xFF138A5A);

  /// Borders and dividers.
  static const bord = Color(0xFFE9E9E9);

  /// Done.
  static const fait = Color(0xFF138A5A);
}

abstract final class Espaces {
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 16.0;
  static const l = 24.0;
  static const xl = 40.0;
}

abstract final class Rayons {
  static const carte = 20.0;
  static const bouton = 18.0;
}

const _police = 'Baloo2';

abstract final class Textes {
  static const marque = TextStyle(
    fontFamily: _police,
    fontSize: 30,
    fontWeight: FontWeight.w800,
    height: 1,
    color: Couleurs.corail,
    shadows: [Shadow(color: Color(0x40FF5151), offset: Offset(2, 2))],
  );
  static const titre = TextStyle(
    fontFamily: _police,
    fontSize: 30,
    fontWeight: FontWeight.w800,
    height: 1.15,
    color: Couleurs.encre,
  );
  static const section = TextStyle(
    fontFamily: _police,
    fontSize: 22,
    fontWeight: FontWeight.w800,
    height: 1.2,
    color: Couleurs.encre,
  );
  static const ligne = TextStyle(
    fontFamily: _police,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.25,
    color: Couleurs.encre,
  );
  static const corps = TextStyle(fontFamily: _police, fontSize: 16, height: 1.4, color: Couleurs.encre);
  static const discret = TextStyle(fontFamily: _police, fontSize: 14, height: 1.35, color: Couleurs.encreDouce);
  static const etiquette = TextStyle(fontFamily: _police, fontSize: 13, fontWeight: FontWeight.w600, height: 1.2);
  static const surtitre = TextStyle(
    fontFamily: _police,
    fontSize: 13,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
    color: Couleurs.violet,
  );
}

/// White card with Buddy's soft border and shadow. `fond` and `bord` switch it to the lilac highlight.
BoxDecoration decorationCarte({Color fond = Couleurs.carte, Color bord = Couleurs.bord}) => BoxDecoration(
  color: fond,
  borderRadius: BorderRadius.circular(Rayons.carte),
  border: Border.all(color: bord),
  boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 3))],
);

ThemeData themePli() {
  final schema = ColorScheme.fromSeed(
    seedColor: Couleurs.corail,
    primary: Couleurs.corail,
    onPrimary: Colors.white,
    error: Couleurs.rouge,
    surface: Couleurs.fond,
    onSurface: Couleurs.encre,
  );
  final boutons = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rayons.bouton));
  const texteBouton = TextStyle(fontFamily: _police, fontSize: 18, fontWeight: FontWeight.w700);
  final champ = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: Couleurs.bord),
  );
  return ThemeData(
    colorScheme: schema,
    scaffoldBackgroundColor: Couleurs.fond,
    fontFamily: _police,
    textTheme: const TextTheme(bodyLarge: Textes.corps, bodyMedium: Textes.corps, bodySmall: Textes.discret),
    appBarTheme: const AppBarTheme(
      backgroundColor: Couleurs.fond,
      foregroundColor: Couleurs.encre,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: Textes.section,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Couleurs.corail,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 56),
        shape: boutons,
        textStyle: texteBouton,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Couleurs.encre,
        minimumSize: const Size(48, 56),
        side: const BorderSide(color: Couleurs.bord, width: 1.5),
        shape: boutons,
        textStyle: texteBouton,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Couleurs.carte,
      labelStyle: Textes.discret,
      border: champ,
      enabledBorder: champ,
      focusedBorder: champ.copyWith(borderSide: const BorderSide(color: Couleurs.corail, width: 2)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Couleurs.corail),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Couleurs.encre,
      contentTextStyle: TextStyle(fontFamily: _police, fontSize: 15, color: Colors.white),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
