import 'package:material_ui/material_ui.dart';

import '../../../core/common/result.dart';
import '../data/auth_repository.dart';

/// Error a mostrar en el formulario. La pantalla lo traduce al idioma de la app; [serverMessage] llega del backend.
sealed class SignInError {
  const SignInError();
}

final class EmptyFieldsError extends SignInError {
  const EmptyFieldsError();
}

final class ConnectionSignInError extends SignInError {
  const ConnectionSignInError();
}

final class ServerSignInError extends SignInError {
  const ServerSignInError(this.serverMessage);

  final String serverMessage;
}

class SignInViewModel extends ChangeNotifier {
  SignInViewModel(this._repository);

  final AuthRepository _repository;

  bool _loading = false;
  SignInError? _error;

  bool get loading => _loading;
  SignInError? get error => _error;

  /// Devuelve true si el backend acepto las credenciales y la sesion quedo guardada.
  Future<bool> signIn(String email, String password) async {
    if (_loading) return false;
    if (email.trim().isEmpty || password.isEmpty) {
      _error = const EmptyFieldsError();
      notifyListeners();
      return false;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    final result = await _repository.signIn(email: email, password: password);
    _loading = false;
    switch (result) {
      case Success():
        notifyListeners();
        return true;
      case Failure(:final message, :final isConnectionError):
        _error = isConnectionError ? const ConnectionSignInError() : ServerSignInError(message);
        notifyListeners();
        return false;
    }
  }
}
