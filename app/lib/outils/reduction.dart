import 'dart:math';

/// Long side kept for a photo of a letter: small print stays readable, and Claude scales larger images down
/// anyway (about 1,568 px), so more pixels only slow the upload.
const coteMaxImage = 2000;

/// Under this, an image already small in pixels is sent as is (a sharp screenshot stays untouched).
const tailleSansReduction = 1536 * 1024;

/// JPEG quality of a shrunk photo: high enough for small print.
const qualiteJpeg = 0.85;

/// Null when the image can go as it is. Otherwise its new size, same ratio, long side at most [coteMaxImage].
({int largeur, int hauteur})? tailleReduite(int largeur, int hauteur, int octets) {
  final cote = max(largeur, hauteur);
  if (cote <= coteMaxImage && octets <= tailleSansReduction) return null;
  final echelle = cote > coteMaxImage ? coteMaxImage / cote : 1.0;
  return (largeur: max(1, (largeur * echelle).round()), hauteur: max(1, (hauteur * echelle).round()));
}
