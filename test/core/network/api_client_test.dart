import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gethics/core/network/api_client.dart';
import 'package:gethics/core/network/api_exception.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('ApiClient', () {
    test('arma la URL con la base, agrega el token y decodifica el JSON', () async {
      late http.Request sent;
      final api = ApiClient(
        baseUrl: 'https://api.example.com',
        tokenProvider: () => 'abc',
        client: MockClient((request) async {
          sent = request;
          return http.Response('{"ok":true,"nombre":"Vacunación"}', 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }),
      );

      final json = await api.get('/api/v1/sanitary-events/upcoming', query: {'days': '7'}) as Map<String, dynamic>;

      expect(sent.url.toString(), 'https://api.example.com/api/v1/sanitary-events/upcoming?days=7');
      expect(sent.headers[HttpHeaders.authorizationHeader], 'Bearer abc');
      expect(json['nombre'], 'Vacunación');
    });

    test('sin token no envia Authorization y el body va en JSON', () async {
      late http.Request sent;
      final api = ApiClient(
        baseUrl: 'https://api.example.com/',
        client: MockClient((request) async {
          sent = request;
          return http.Response('', 204);
        }),
      );

      final result = await api.post('auth/login', body: {'email': 'a@b.com'});

      expect(result, isNull);
      expect(sent.headers.containsKey(HttpHeaders.authorizationHeader), isFalse);
      expect(jsonDecode(sent.body), {'email': 'a@b.com'});
    });

    test('un error del backend se convierte en ApiException con su message', () async {
      final api = ApiClient(
        baseUrl: 'https://api.example.com',
        client: MockClient((_) async => http.Response('{"message":"Credenciales invalidas"}', 401)),
      );

      expect(
        () => api.post('auth/login'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.message, 'message', 'Credenciales invalidas')
            .having((e) => e.isConnectionError, 'isConnectionError', false)),
      );
    });

    test('un cuerpo de error que no es JSON deja el message vacio', () async {
      final api = ApiClient(
        baseUrl: 'https://api.example.com',
        client: MockClient((_) async => http.Response('<html>502</html>', 502)),
      );

      expect(() => api.get('x'), throwsA(isA<ApiException>().having((e) => e.message, 'message', '')));
    });

    test('sin conexion lanza un error de conexion', () async {
      final api = ApiClient(
        baseUrl: 'https://api.example.com',
        client: MockClient((_) async => throw const SocketException('sin red')),
      );

      expect(() => api.get('x'), throwsA(isA<ApiException>().having((e) => e.isConnectionError, 'isConnectionError', true)));
    });
  });
}
