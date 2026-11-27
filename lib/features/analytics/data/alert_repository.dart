import '../../../core/common/result.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../domain/trend_alert.dart';

/// Acceso a los Web Services del contexto analytics.
class AlertRepository {
  AlertRepository(this._api);

  final ApiClient _api;

  /// US-21: alertas por tendencia YA almacenadas del propietario, de la mas reciente a la mas antigua (orden del
  /// backend). El backend no las genera al consultar: las crea su analisis periodico, hoy deshabilitado y sin
  /// detectores. Un propietario sin alertas responde 200 con la lista vacia; un [ownerId] ausente o que no es UUID, 400.
  /// El endpoint no valida que el propietario corresponda a quien consulta: el llamador debe obtener [ownerId] de una
  /// relacion legitima (p. ej. un cliente asignado), nunca de un valor fijo.
  Future<Result<List<TrendAlert>>> getAlerts(String ownerId) async {
    try {
      final json = await _api.get('api/v1/alerts', query: {'ownerId': ownerId}) as Map<String, dynamic>;
      final items = ((json['alerts'] as List<dynamic>?) ?? const []).cast<Map<String, dynamic>>();
      return Success(items.map(_toAlert).toList());
    } on ApiException catch (e) {
      return Failure(e.message, isConnectionError: e.isConnectionError);
    }
  }

  static TrendAlert _toAlert(Map<String, dynamic> json) => TrendAlert(
        id: json['id'] as String,
        trendId: json['trendId'] as String? ?? '',
        type: TrendType.fromName(json['trendType'] as String?),
        riskLevel: RiskLevel.fromName(json['riskLevel'] as String?),
        message: json['message'] as String? ?? '',
        status: AlertStatus.fromName(json['status'] as String?),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      );
}
