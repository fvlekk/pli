import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'reduction.dart';

/// Shrinks a photo in the browser before upload: JPEG, long side at most 2000 px, the camera's orientation applied.
/// Re-encoding also drops the photo's metadata (GPS position included).
///
/// Null: send the original (already small, or a format this browser cannot decode).
Future<Uint8List?> reduireImage(Uint8List octets) async {
  try {
    final image = await web.window
        .createImageBitmap(web.Blob([octets.toJS].toJS), web.ImageBitmapOptions(imageOrientation: 'from-image'))
        .toDart;
    final taille = tailleReduite(image.width, image.height, octets.length);
    if (taille == null) {
      image.close();
      return null;
    }
    final toile = web.HTMLCanvasElement()
      ..width = taille.largeur
      ..height = taille.hauteur;
    final contexte = toile.getContext('2d')! as web.CanvasRenderingContext2D;
    // JPEG has no transparency: a white page behind a transparent PNG, not a black one.
    contexte
      ..fillStyle = 'white'.toJS
      ..fillRect(0, 0, taille.largeur, taille.hauteur)
      ..drawImage(image, 0, 0, taille.largeur, taille.hauteur);
    image.close();
    final url = toile.toDataURL('image/jpeg', qualiteJpeg.toJS);
    final reduite = base64Decode(url.substring(url.indexOf(',') + 1));
    return reduite.length < octets.length ? reduite : null;
  } catch (_) {
    return null;
  }
}
