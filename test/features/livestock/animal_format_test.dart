import 'package:flutter_test/flutter_test.dart';
import 'package:gethics/features/livestock/presentation/animal_format.dart';

void main() {
  final today = DateTime(2026, 11, 25);

  group('monthsBetween', () {
    test('cuenta meses completos', () {
      expect(monthsBetween(DateTime(2022, 5, 12), today), 54);
      expect(monthsBetween(DateTime(2026, 5, 25), today), 6);
    });

    test('un mes no esta completo hasta llegar al dia de nacimiento', () {
      expect(monthsBetween(DateTime(2026, 10, 26), today), 0);
      expect(monthsBetween(DateTime(2026, 10, 25), today), 1);
    });

    test('sin fecha o con fecha futura devuelve null', () {
      expect(monthsBetween(null, today), isNull);
      expect(monthsBetween(DateTime(2026, 11, 26), today), isNull);
    });

    test('el mismo dia es menos de un mes', () {
      expect(monthsBetween(today, today), 0);
    });
  });

  test('formatBirthDate usa dia/mes/anio y sin fecha muestra el guion', () {
    expect(formatBirthDate(DateTime(2022, 5, 2)), '02/05/2022');
    expect(formatBirthDate(null), noData);
  });

  test('formatWeight quita los decimales cuando el peso es entero', () {
    expect(formatWeight(650), '650');
    expect(formatWeight(650.5), '650.5');
  });
}
