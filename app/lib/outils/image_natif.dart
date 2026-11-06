import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'reduction.dart';

/// Shrinks an imported image on the phone, as `image_web.dart` does in the browser: JPEG, long side at most 2000 px, the
/// camera's orientation applied. Working from the decoded pixels also drops the metadata (GPS position included).
///
/// Null: send the original (already small, or a format this phone cannot decode).
Future<Uint8List?> reduireImage(Uint8List octets) async {
  try {
    final codec = await ui.instantiateImageCodec(octets);
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    final taille = tailleReduite(image.width, image.height, octets.length);
    if (taille == null) {
      image.dispose();
      return null;
    }
    final (largeur, hauteur) = (taille.largeur, taille.hauteur);
    final cadre = ui.Rect.fromLTWH(0, 0, largeur.toDouble(), hauteur.toDouble());
    final enregistreur = ui.PictureRecorder();
    // JPEG has no transparency: a white page behind a transparent PNG, not a black one.
    ui.Canvas(enregistreur)
      ..drawRect(cadre, ui.Paint()..color = const ui.Color(0xFFFFFFFF))
      ..drawImageRect(
        image,
        ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        cadre,
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );
    image.dispose();
    final dessin = enregistreur.endRecording();
    final reduite = await dessin.toImage(largeur, hauteur);
    dessin.dispose();
    final pixels = await reduite.toByteData();
    reduite.dispose();
    // Encoding takes a moment on a phone: not on the thread that draws the screen.
    final jpeg = await compute(_versJpeg, (pixels!.buffer, largeur, hauteur));
    return jpeg.length < octets.length ? jpeg : null;
  } catch (_) {
    return null;
  }
}

Uint8List _versJpeg((ByteBuffer, int, int) image) {
  final (pixels, largeur, hauteur) = image;
  return img.encodeJpg(
    img.Image.fromBytes(width: largeur, height: hauteur, bytes: pixels, numChannels: 4),
    quality: (qualiteJpeg * 100).round(),
  );
}
