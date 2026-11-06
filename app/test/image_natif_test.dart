import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pli/outils/image_natif.dart';

void main() {
  /// Noise compresses badly: as heavy as a real photo.
  img.Image bruit(int largeur, int hauteur) {
    final image = img.Image(width: largeur, height: hauteur);
    var graine = 7;
    for (final p in image) {
      graine = (graine * 1103515245 + 12345) & 0x7fffffff;
      p
        ..r = graine & 255
        ..g = (graine >> 8) & 255
        ..b = (graine >> 16) & 255;
    }
    return image;
  }

  testWidgets('a heavy photo comes back lighter, as a JPEG of 2000 px on its long side', (tester) async {
    final origine = img.encodeJpg(bruit(3000, 1500), quality: 100);
    final reduite = await tester.runAsync(() => reduireImage(origine));
    expect(reduite!.length, lessThan(origine.length));
    expect(img.JpegDecoder().isValidFile(reduite), isTrue);
    final decodee = img.decodeJpg(reduite)!;
    expect((decodee.width, decodee.height), (2000, 1000));
  });

  testWidgets('the camera orientation is applied, and metadata does not survive', (tester) async {
    final photo = bruit(3000, 1000);
    photo.exif.imageIfd.orientation = 6; // Held upright: the file is stored on its side.
    photo.exif.gpsIfd['GPSLatitudeRef'] = 'N';
    final reduite = await tester.runAsync(() => reduireImage(img.encodeJpg(photo, quality: 100)));
    final decodee = img.decodeJpg(reduite!)!;
    expect((decodee.width, decodee.height), (667, 2000));
    expect(decodee.exif.isEmpty, isTrue);
  });

  testWidgets('transparency becomes a white page', (tester) async {
    final image = bruit(2600, 1300).convert(numChannels: 4);
    for (var x = 0; x < 200; x++) {
      for (var y = 0; y < 200; y++) {
        image.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
    final reduite = await tester.runAsync(() => reduireImage(img.encodePng(image)));
    final coin = img.decodeJpg(reduite!)!.getPixel(10, 10);
    expect(coin.r, greaterThan(240));
    expect(coin.g, greaterThan(240));
    expect(coin.b, greaterThan(240));
  });

  testWidgets('colours stay in their channels', (tester) async {
    final image = bruit(2600, 1300);
    for (var x = 0; x < 400; x++) {
      for (var y = 0; y < 400; y++) {
        image.setPixelRgb(x, y, 230, 20, 20);
      }
    }
    final reduite = await tester.runAsync(() => reduireImage(img.encodeJpg(image, quality: 100)));
    final pixel = img.decodeJpg(reduite!)!.getPixel(50, 50);
    expect(pixel.r, greaterThan(200));
    expect(pixel.b, lessThan(60));
  });

  testWidgets('a small image is left alone', (tester) async {
    final octets = img.encodePng(img.Image(width: 300, height: 400));
    expect(await tester.runAsync(() => reduireImage(octets)), isNull);
  });

  testWidgets('what cannot be decoded goes as is, without an error', (tester) async {
    expect(await tester.runAsync(() => reduireImage(Uint8List.fromList([1, 2, 3, 4]))), isNull);
  });
}
