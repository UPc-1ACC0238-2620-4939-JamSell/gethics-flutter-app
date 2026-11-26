import 'package:shared_preferences/shared_preferences.dart';

/// Sesion del usuario guardada en el dispositivo: token JWT, rol y nombre para mostrar.
class SessionStorage {
  SessionStorage(this._preferences);

  static const _tokenKey = 'session.token';
  static const _roleKey = 'session.role';
  static const _nameKey = 'session.name';

  final SharedPreferences _preferences;

  String? get token => _preferences.getString(_tokenKey);
  String? get role => _preferences.getString(_roleKey);
  String? get name => _preferences.getString(_nameKey);

  bool get isSignedIn => (token ?? '').isNotEmpty;

  Future<void> save({required String token, required String role, required String name}) async {
    await _preferences.setString(_tokenKey, token);
    await _preferences.setString(_roleKey, role);
    await _preferences.setString(_nameKey, name);
  }

  Future<void> clear() async {
    await _preferences.remove(_tokenKey);
    await _preferences.remove(_roleKey);
    await _preferences.remove(_nameKey);
  }
}
