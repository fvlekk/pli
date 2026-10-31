import 'package:intl/intl.dart';

/// Deadlines are calendar days, not instants: all maths happen on UTC dates so a daylight-saving change can
/// never turn "1 day left" into "0".
DateTime jourUtc(DateTime d) => DateTime.utc(d.year, d.month, d.day);

int joursRestants(DateTime limite, DateTime aujourdhui) => jourUtc(limite).difference(jourUtc(aujourdhui)).inDays;

enum Horizon { enRetard, cetteSemaine, ceMois, plusTard }

Horizon horizonDe(int jours) {
  if (jours < 0) return Horizon.enRetard;
  if (jours <= 7) return Horizon.cetteSemaine;
  if (jours <= 31) return Horizon.ceMois;
  return Horizon.plusTard;
}

bool estUrgent(int jours) => jours <= 7;

String dateCourte(DateTime d) => DateFormat('d MMM', 'fr').format(d);

String dateLongue(DateTime d) => DateFormat('EEEE d MMMM y', 'fr').format(d);

/// "90 €", "1 248,50 €". The fonts lack the narrow no-break space intl uses, so it becomes a regular one.
String euros(double montant) {
  final entier = montant == montant.roundToDouble();
  final format = NumberFormat.currency(locale: 'fr', symbol: '€', decimalDigits: entier ? 0 : 2);
  return format.format(montant).replaceAll(' ', ' ');
}

/// "05/11/26", like the dates on Buddy's cards.
String dateChiffres(DateTime d) => DateFormat('dd/MM/yy', 'fr').format(d);

/// The countdown pill: "En retard", "Aujourd'hui", "Demain", "Dans 3 jours".
String rebours(int jours) => switch (jours) {
  < 0 => 'En retard',
  0 => "Aujourd'hui",
  1 => 'Demain',
  _ => 'Dans $jours jours',
};
