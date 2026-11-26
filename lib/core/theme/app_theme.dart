import 'package:material_ui/material_ui.dart';

/// Colores de los Style Guidelines de Gethics (los mismos que la app Android).
abstract final class GethicsColors {
  static const wine = Color(0xFF733336); // primario: botones, links, CTA
  static const offWhite = Color(0xFFFAFAFA); // texto sobre el primario
  static const ink = Color(0xFF1A1C19); // texto principal
  static const inkVariant = Color(0xFF43483F); // texto secundario
  static const mint = Color(0xFFE8F3E8); // fondos de seccion
  static const alertBackground = Color(0xFFFFF4E0); // avisos de atencion
  static const alertText = Color(0xFFB26A00);
}

ThemeData buildGethicsTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: GethicsColors.wine,
    primary: GethicsColors.wine,
    onPrimary: GethicsColors.offWhite,
    surface: Colors.white,
    onSurface: GethicsColors.ink,
    onSurfaceVariant: GethicsColors.inkVariant,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFF5F7F4),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
    ),
  );
}
