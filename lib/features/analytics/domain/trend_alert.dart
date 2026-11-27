T? _byName<T extends Enum>(List<T> values, String? name) {
  for (final value in values) {
    if (value.name.toUpperCase() == name?.toUpperCase()) return value;
  }
  return null;
}

/// Origen de la tendencia que genero la alerta (TrendType del backend).
enum TrendType {
  sanitary,
  financial,
  combined;

  /// Valor desconocido o ausente: null, para no mostrar un tipo inventado.
  static TrendType? fromName(String? value) => _byName(values, value);
}

/// Nivel de riesgo de la tendencia (RiskLevel del backend), de menor a mayor.
enum RiskLevel {
  low,
  medium,
  high,
  critical;

  static RiskLevel? fromName(String? value) => _byName(values, value);
}

/// Estado de la alerta (AlertStatus del backend). La app solo lo muestra: no hay endpoint para cambiarlo.
enum AlertStatus {
  pending,
  sent,
  read;

  static AlertStatus? fromName(String? value) => _byName(values, value);
}

/// US-21: alerta generada por una tendencia (AlertResource). Los campos que el backend envie vacios o con un valor que
/// la app no conoce quedan en null y la pantalla los omite.
class TrendAlert {
  const TrendAlert({
    required this.id,
    required this.trendId,
    required this.type,
    required this.riskLevel,
    required this.message,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String trendId;
  final TrendType? type;
  final RiskLevel? riskLevel;

  /// Texto generado por el backend; se muestra tal cual.
  final String message;
  final AlertStatus? status;

  /// Momento de creacion (UTC en el backend); null si no llego o no se pudo leer.
  final DateTime? createdAt;
}
