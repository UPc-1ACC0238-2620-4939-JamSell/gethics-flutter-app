/// Texto que se muestra cuando falta un dato; no se inventa ninguno.
const String noData = '—';

/// Meses completos entre [birth] y [today]; null si no hay fecha de nacimiento o es posterior a [today].
/// [today] se inyecta para poder probarlo.
int? monthsBetween(DateTime? birth, DateTime today) {
  if (birth == null) return null;
  final birthDay = DateTime(birth.year, birth.month, birth.day);
  final day = DateTime(today.year, today.month, today.day);
  if (birthDay.isAfter(day)) return null;
  var months = (day.year - birthDay.year) * 12 + day.month - birthDay.month;
  if (day.day < birthDay.day) months -= 1;
  return months;
}

/// "12/05/2022" a partir de la fecha de nacimiento; sin fecha, [noData].
String formatBirthDate(DateTime? date) {
  if (date == null) return noData;
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)}/${date.year}';
}

/// "650" o "650.5": sin decimales cuando el peso es entero.
String formatWeight(double kg) => kg == kg.roundToDouble() ? kg.toStringAsFixed(0) : kg.toStringAsFixed(1);
