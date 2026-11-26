import '../../../core/common/result.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/session/session_storage.dart';
import '../domain/authenticated_user.dart';
import '../domain/role.dart';

/// Inicio de sesion contra POST /auth/login (AuthenticatedUserResource): guarda el token y los datos del usuario.
class AuthRepository {
  AuthRepository(this._api, this._session);

  final ApiClient _api;
  final SessionStorage _session;

  Future<Result<AuthenticatedUser>> signIn({required String email, required String password}) async {
    try {
      final json = await _api.post('auth/login', body: {'email': email.trim(), 'password': password}) as Map<String, dynamic>;
      final userJson = json['user'] as Map<String, dynamic>;
      final user = AuthenticatedUser(
        id: (userJson['id'] as num).toInt(),
        name: userJson['name'] as String? ?? '',
        email: userJson['email'] as String? ?? email.trim(),
        role: Role.fromName(userJson['role'] as String?),
      );
      await _session.save(token: json['token'] as String, role: user.role.name.toUpperCase(), name: user.name);
      return Success(user);
    } on ApiException catch (e) {
      return Failure(e.message, isConnectionError: e.isConnectionError);
    }
  }

  Future<void> signOut() => _session.clear();
}
