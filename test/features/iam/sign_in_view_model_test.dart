import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gethics/core/network/api_client.dart';
import 'package:gethics/core/session/session_storage.dart';
import 'package:gethics/features/iam/data/auth_repository.dart';
import 'package:gethics/features/iam/presentation/sign_in_view_model.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SignInViewModel> _viewModel(Future<http.Response> Function(http.Request) handler) async {
  SharedPreferences.setMockInitialValues({});
  final session = SessionStorage(await SharedPreferences.getInstance());
  final api = ApiClient(baseUrl: 'https://api.example.com', client: MockClient(handler));
  return SignInViewModel(AuthRepository(api, session));
}

void main() {
  test('campos vacios no llaman al backend', () async {
    var calls = 0;
    final viewModel = await _viewModel((_) async {
      calls++;
      return http.Response('{}', 200);
    });

    expect(await viewModel.signIn('  ', ''), isFalse);
    expect(viewModel.error, isA<EmptyFieldsError>());
    expect(calls, 0);
  });

  test('credenciales validas devuelven true y limpian el error', () async {
    final viewModel = await _viewModel((_) async => http.Response(
        '{"token":"t","user":{"id":1,"name":"Ana","email":"a@b.com","role":"VETERINARIO"}}', 200));

    expect(await viewModel.signIn('a@b.com', 'secreto123'), isTrue);
    expect(viewModel.error, isNull);
    expect(viewModel.loading, isFalse);
  });

  test('un error del backend queda como ServerSignInError con su mensaje', () async {
    final viewModel = await _viewModel((_) async => http.Response('{"message":"Credenciales invalidas"}', 401));

    expect(await viewModel.signIn('a@b.com', 'x'), isFalse);
    expect(viewModel.error, isA<ServerSignInError>().having((e) => e.serverMessage, 'serverMessage', 'Credenciales invalidas'));
  });

  test('sin conexion queda como ConnectionSignInError', () async {
    final viewModel = await _viewModel((_) async => throw const SocketException('sin red'));

    expect(await viewModel.signIn('a@b.com', 'x'), isFalse);
    expect(viewModel.error, isA<ConnectionSignInError>());
  });
}
