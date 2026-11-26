/// Resultado de una operacion de repositorio: la capa de presentacion no maneja excepciones.
sealed class Result<T> {
  const Result();
}

final class Success<T> extends Result<T> {
  const Success(this.data);

  final T data;
}

/// [message] es el texto del backend; vacio cuando no hay uno y la pantalla debe mostrar su texto generico.
/// [isConnectionError] permite mostrar el aviso de conexion en el idioma de la app.
final class Failure<T> extends Result<T> {
  const Failure(this.message, {this.isConnectionError = false});

  final String message;
  final bool isConnectionError;
}
