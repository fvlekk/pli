import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pli/outils/dates.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  test('days left count calendar days, whatever the time of day', () {
    expect(joursRestants(DateTime(2026, 10, 18), DateTime(2026, 10, 12, 23, 59)), 6);
    expect(joursRestants(DateTime(2026, 10, 12), DateTime(2026, 10, 12, 8)), 0);
  });

  test('a daylight-saving change does not eat a day', () {
    // Paris goes back one hour in the night of 24 to 25 October 2026.
    expect(joursRestants(DateTime(2026, 10, 26), DateTime(2026, 10, 25)), 1);
    expect(joursRestants(DateTime(2027, 3, 29), DateTime(2027, 3, 27)), 2);
  });

  test('horizons', () {
    expect(horizonDe(-1), Horizon.enRetard);
    expect(horizonDe(0), Horizon.cetteSemaine);
    expect(horizonDe(7), Horizon.cetteSemaine);
    expect(horizonDe(8), Horizon.ceMois);
    expect(horizonDe(32), Horizon.plusTard);
  });

  test('amounts in French, without a glyph the fonts lack', () {
    expect(euros(90), '90 €');
    expect(euros(1248.5), '1 248,50 €');
    expect(euros(1248.5).contains(' '), isFalse);
  });

  test('countdown wording', () {
    expect(compteARebours(-2).unite, 'en retard');
    expect(compteARebours(0).unite, "aujourd'hui");
    expect(compteARebours(1), (nombre: '1', unite: 'jour'));
    expect(compteARebours(12), (nombre: '12', unite: 'jours'));
  });

  test('short French dates', () {
    expect(dateCourte(DateTime(2026, 11, 15)), '15 nov.');
  });
}
