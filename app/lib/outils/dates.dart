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

/// What the postmark says: "aujourd'hui", "demain", "3 jours", "en retard".
({String nombre, String unite}) compteARebours(int jours) {
  if (jours < 0) return (nombre: '!', unite: 'en retard');
  if (jours == 0) return (nombre: '0', unite: "aujourd'hui");
  if (jours == 1) return (nombre: '1', unite: 'jour');
  return (nombre: '$jours', unite: 'jours');
}
