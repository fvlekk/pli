import 'package:flutter/material.dart';

/// Design tokens. Widgets use these, never raw colors.
///
/// The palette comes from French administrative mail: the blue-grey of a window envelope, the violet ink of
/// a town-hall stamp, sealing-wax red kept for what is urgent.
abstract final class Couleurs {
  /// Background: the glassine of a window envelope.
  static const fenetre = Color(0xFFE6ECF1);

  /// Surfaces: the letter itself.
  static const feuille = Color(0xFFFFFFFF);

  /// Text.
  static const encre = Color(0xFF23214A);

  /// Secondary text (5.9:1 on white).
  static const encreDouce = Color(0xFF5E6180);

  /// Accent: stamp ink. Primary actions and postmarks.
  static const tampon = Color(0xFF5C47A8);

  /// Urgent: less than a week left, or late. Never decorative.
  static const cire = Color(0xFFB8352B);

  /// Fold creases and dividers.
  static const pli = Color(0xFFC9D3DC);

  /// Done.
  static const fait = Color(0xFF2F7D5B);
}

abstract final class Polices {
  static const titre = 'YoungSerif';
  static const texte = 'Atkinson';
}

abstract final class Espaces {
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 16.0;
  static const l = 24.0;
  static const xl = 40.0;
}

/// Type scale (1.25 ratio from 16).
abstract final class Textes {
  static const marque = TextStyle(fontFamily: Polices.titre, fontSize: 31, height: 1.1, color: Couleurs.encre);
  static const titre = TextStyle(fontFamily: Polices.titre, fontSize: 25, height: 1.2, color: Couleurs.encre);
  static const volet = TextStyle(fontFamily: Polices.titre, fontSize: 20, height: 1.25, color: Couleurs.encre);
  static const ligne = TextStyle(fontFamily: Polices.titre, fontSize: 17, height: 1.3, color: Couleurs.encre);
  static const corps = TextStyle(fontFamily: Polices.texte, fontSize: 16, height: 1.45, color: Couleurs.encre);
  static const discret = TextStyle(fontFamily: Polices.texte, fontSize: 14, height: 1.4, color: Couleurs.encreDouce);
  static const montant = TextStyle(
    fontFamily: Polices.titre,
    fontSize: 17,
    color: Couleurs.encre,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

ThemeData themePli() {
  final schema = ColorScheme.fromSeed(
    seedColor: Couleurs.tampon,
    primary: Couleurs.tampon,
    onPrimary: Couleurs.feuille,
    error: Couleurs.cire,
    surface: Couleurs.feuille,
    onSurface: Couleurs.encre,
  );
  final boutons = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
  return ThemeData(
    colorScheme: schema,
    scaffoldBackgroundColor: Couleurs.fenetre,
    fontFamily: Polices.texte,
    textTheme: const TextTheme(bodyLarge: Textes.corps, bodyMedium: Textes.corps, bodySmall: Textes.discret),
    appBarTheme: const AppBarTheme(
      backgroundColor: Couleurs.fenetre,
      foregroundColor: Couleurs.encre,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: Textes.volet,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Couleurs.tampon,
        foregroundColor: Couleurs.feuille,
        minimumSize: const Size(48, 52),
        shape: boutons,
        textStyle: const TextStyle(fontFamily: Polices.texte, fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Couleurs.encre,
        minimumSize: const Size(48, 52),
        side: const BorderSide(color: Couleurs.pli, width: 1.5),
        shape: boutons,
        textStyle: const TextStyle(fontFamily: Polices.texte, fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Couleurs.feuille,
      labelStyle: Textes.discret,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Couleurs.pli),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Couleurs.pli),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Couleurs.tampon, width: 2),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Couleurs.encre,
      contentTextStyle: TextStyle(fontFamily: Polices.texte, fontSize: 15, color: Couleurs.feuille),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
