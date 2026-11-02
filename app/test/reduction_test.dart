import 'package:flutter_test/flutter_test.dart';
import 'package:pli/outils/reduction.dart';

void main() {
  test('a small, light image is sent as is', () {
    expect(tailleReduite(1200, 1600, 400 * 1024), isNull);
    expect(tailleReduite(coteMaxImage, 1000, tailleSansReduction), isNull, reason: 'limits are inclusive');
  });

  test('a phone photo is brought down to 2000 px on its long side, same ratio', () {
    expect(tailleReduite(4032, 3024, 6 * 1024 * 1024), (largeur: 2000, hauteur: 1500));
    expect(tailleReduite(3024, 4032, 6 * 1024 * 1024), (largeur: 1500, hauteur: 2000), reason: 'portrait');
  });

  test('a heavy image already small in pixels is re-encoded, never enlarged', () {
    expect(tailleReduite(1800, 1200, 3 * 1024 * 1024), (largeur: 1800, hauteur: 1200));
  });

  test('an extreme panorama keeps at least one pixel on its short side', () {
    expect(tailleReduite(100000, 10, 2 * 1024 * 1024), (largeur: 2000, hauteur: 1));
  });
}
