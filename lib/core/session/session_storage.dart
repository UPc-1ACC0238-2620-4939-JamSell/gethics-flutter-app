import 'package:shared_preferences/shared_preferences.dart';

/// Sesion del usuario guardada en el dispositivo: token JWT, id de IAM, rol y nombre para mostrar.
class SessionStorage {
  SessionStorage(this._preferences);

  static const _tokenKey = 'session.token';
  static const _userIdKey = 'session.userId';
  static const _roleKey = 'session.role';
  static const _nameKey = 'session.name';

  final SharedPreferences _preferences;

  String? get token => _preferences.getString(_tokenKey);

  /// Id de IAM (Long del backend, como texto). Identifica de quien son las operaciones offline (US-35); no es un
  /// ownerId ni un veterinarianId. null en una sesion iniciada antes de US-35: hasta volver a iniciar sesion no hay cola.
  String? get userId => _preferences.getString(_userIdKey);
  String? get role => _preferences.getString(_roleKey);
  String? get name => _preferences.getString(_nameKey);

  bool get isSignedIn => (token ?? '').isNotEmpty;

  Future<void> save({required String token, String? userId, required String role, required String name}) async {
    await _preferences.setString(_tokenKey, token);
    if (userId == null) {
      await _preferences.remove(_userIdKey);
    } else {
      await _preferences.setString(_userIdKey, userId);
    }
    await _preferences.setString(_roleKey, role);
    await _preferences.setString(_nameKey, name);
  }

  Future<void> clear() async {
    await _preferences.remove(_tokenKey);
    await _preferences.remove(_userIdKey);
    await _preferences.remove(_roleKey);
    await _preferences.remove(_nameKey);
  }
}
