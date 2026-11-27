import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/animal.dart';
import 'animal_texts.dart';

/// Pastilla con el estado del animal (Activo, Vendido...). Sin estado o desconocido no dibuja nada.
class AnimalStatusBadge extends StatelessWidget {
  const AnimalStatusBadge({super.key, required this.status});

  final AnimalStatus? status;

  @override
  Widget build(BuildContext context) {
    final current = status;
    if (current == null) return const SizedBox.shrink();
    final (background, foreground) = switch (current) {
      AnimalStatus.active => (GethicsColors.mint, const Color(0xFF2E6B3A)),
      AnimalStatus.sold => (GethicsColors.alertBackground, GethicsColors.alertText),
      AnimalStatus.deceased => (const Color(0xFFF3E3E4), GethicsColors.wine),
      AnimalStatus.inactive => (const Color(0xFFEDEFED), GethicsColors.inkVariant),
    };
    return DecoratedBox(
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(50)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          statusLabel(AppLocalizations.of(context), current),
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: foreground),
        ),
      ),
    );
  }
}
