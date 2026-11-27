import '../../../l10n/app_localizations.dart';
import '../domain/animal.dart';
import 'animal_format.dart';

/// Estado de un animal concreto en singular ("Activo" / "Active").
String statusLabel(AppLocalizations l10n, AnimalStatus status) => switch (status) {
      AnimalStatus.active => l10n.animalStatusActive,
      AnimalStatus.sold => l10n.animalStatusSold,
      AnimalStatus.deceased => l10n.animalStatusDeceased,
      AnimalStatus.inactive => l10n.animalStatusInactive,
    };

/// Estado como opcion del filtro, en plural ("Activos" / "Active").
String statusFilterLabel(AppLocalizations l10n, AnimalStatus status) => switch (status) {
      AnimalStatus.active => l10n.filterActive,
      AnimalStatus.sold => l10n.filterSold,
      AnimalStatus.deceased => l10n.filterDeceased,
      AnimalStatus.inactive => l10n.filterInactive,
    };

/// "Macho" / "Hembra"; sin dato o desconocido, "Sin especificar".
String sexText(AppLocalizations l10n, String? sex) => switch (sex) {
      'MALE' => l10n.animalSexMale,
      'FEMALE' => l10n.animalSexFemale,
      _ => l10n.animalSexUnspecified,
    };

/// "4 años", "8 meses" o "Menos de 1 mes"; sin fecha de nacimiento valida, [noData].
String ageText(AppLocalizations l10n, DateTime? birthDate, DateTime today) {
  final months = monthsBetween(birthDate, today);
  if (months == null) return noData;
  if (months >= 12) return l10n.animalAgeYears(months ~/ 12);
  if (months >= 1) return l10n.animalAgeMonths(months);
  return l10n.animalAgeLessThanMonth;
}
