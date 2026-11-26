import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gethics/core/common/result.dart';
import 'package:gethics/core/network/api_client.dart';
import 'package:gethics/core/session/session_storage.dart';
import 'package:gethics/features/iam/data/auth_repository.dart';
import 'package:gethics/features/iam/domain/authenticated_user.dart';
import 'package:gethics/features/iam/domain/role.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _loginResponse = '''
{"token":"jwt-token","refreshToken":"r","tokenType":"Bearer","expiresIn":3600,
 "user":{"id":7,"name":"Ana Vet","email":"ana@vet.pe","role":"VETERINARIO","phone":null,"photoUrl":null}}''';

Future<SessionStorage> _session() async {
  SharedPreferences.setMockInitialValues({});
  return SessionStorage(await SharedPreferences.getInstance());
}

void main() {
  test('iniciar sesion envia las credenciales y guarda el token, el rol y el nombre', () async {
    final session = await _session();
    late http.Request sent;
    final api = ApiClient(
      baseUrl: 'https://api.example.com',
      client: MockClient((request) async {
        sent = request;
        return http.Response(_loginResponse, 200);
      }),
    );

    final result = await AuthRepository(api, session).signIn(email: ' ana@vet.pe ', password: 'secreto123');

    expect(sent.url.path, '/auth/login');
    expect(jsonDecode(sent.body), {'email': 'ana@vet.pe', 'password': 'secreto123'});
    final user = (result as Success<AuthenticatedUser>).data;
    expect(user.id, 7);
    expect(user.role, Role.veterinario);
    expect(session.token, 'jwt-token');
    expect(session.role, 'VETERINARIO');
    expect(session.name, 'Ana Vet');
    expect(session.isSignedIn, isTrue);
  });

  test('credenciales invalidas devuelven el message del backend y no guardan sesion', () async {
    final session = await _session();
    final api = ApiClient(
      baseUrl: 'https://api.example.com',
      client: MockClient((_) async => http.Response('{"message":"Credenciales invalidas"}', 401)),
    );

    final result = await AuthRepository(api, session).signIn(email: 'a@b.com', password: 'x');

    expect(result, isA<Failure<AuthenticatedUser>>().having((f) => f.message, 'message', 'Credenciales invalidas'));
    expect(session.isSignedIn, isFalse);
  });

  test('cerrar sesion borra los datos guardados', () async {
    final session = await _session();
    await session.save(token: 't', role: 'VETERINARIO', name: 'Ana');

    await AuthRepository(ApiClient(client: MockClient((_) async => http.Response('', 200))), session).signOut();

    expect(session.isSignedIn, isFalse);
    expect(session.name, isNull);
  });

  test('Role.fromName reconoce los roles del backend', () {
    expect(Role.fromName('VETERINARIO'), Role.veterinario);
    expect(Role.fromName('GANADERO'), Role.ganadero);
    expect(Role.fromName(null), Role.ganadero);
  });
}
