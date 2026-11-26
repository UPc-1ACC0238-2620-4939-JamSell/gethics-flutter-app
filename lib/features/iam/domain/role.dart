/// Mismos valores que Role.java del backend (iam).
enum Role {
  ganadero,
  veterinario;

  /// Rol a partir del texto del backend (GANADERO, VETERINARIO). Desconocido o sin dato: ganadero, como en Android.
  static Role fromName(String? value) =>
      Role.values.firstWhere((role) => role.name.toUpperCase() == value?.toUpperCase(), orElse: () => Role.ganadero);
}
