/// Error de una solicitud HTTP. [statusCode] es null cuando no hubo respuesta (sin conexion o tiempo agotado).
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  const ApiException.connection() : message = '', statusCode = null;

  /// Mensaje del backend ({"message": "..."}); vacio si no envio uno.
  final String message;
  final int? statusCode;

  bool get isConnectionError => statusCode == null;

  @override
  String toString() => 'ApiException($statusCode, $message)';
}
