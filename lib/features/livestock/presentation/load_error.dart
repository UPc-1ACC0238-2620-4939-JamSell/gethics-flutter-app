/// Error de carga a mostrar con la opcion de reintentar. [message] viene del backend y puede estar vacio;
/// [isConnection] permite mostrar el aviso de conexion en el idioma de la app.
class LoadError {
  const LoadError(this.message, {this.isConnection = false});

  final String message;
  final bool isConnection;
}
