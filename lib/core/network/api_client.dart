import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'api_exception.dart';

/// Cliente JSON de los Web Services de Gethics. Agrega el token JWT de la sesion y convierte los errores del backend
/// ({"message": "..."}) y de red en [ApiException].
class ApiClient {
  ApiClient({
    required http.Client client,
    String baseUrl = apiBaseUrl,
    String? Function()? tokenProvider,
    Duration timeout = apiTimeout,
  })  : _client = client, // ignore: prefer_initializing_formals
        _baseUri = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
        _tokenProvider = tokenProvider, // ignore: prefer_initializing_formals
        _timeout = timeout; // ignore: prefer_initializing_formals

  final http.Client _client;
  final Uri _baseUri;
  final String? Function()? _tokenProvider;
  final Duration _timeout;

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _send(() => _client.get(_uri(path, query), headers: _headers()));

  Future<dynamic> post(String path, {Object? body}) =>
      _send(() => _client.post(_uri(path, null), headers: _headers(), body: body == null ? null : jsonEncode(body)));

  Uri _uri(String path, Map<String, String>? query) {
    final relative = path.startsWith('/') ? path.substring(1) : path;
    final uri = _baseUri.resolve(relative);
    return query == null || query.isEmpty ? uri : uri.replace(queryParameters: query);
  }

  Map<String, String> _headers() {
    final token = _tokenProvider?.call();
    return {
      HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
      HttpHeaders.acceptHeader: 'application/json',
      if (token != null && token.isNotEmpty) HttpHeaders.authorizationHeader: 'Bearer $token',
    };
  }

  Future<dynamic> _send(Future<http.Response> Function() request) async {
    final http.Response response;
    try {
      response = await request().timeout(_timeout);
    } on SocketException {
      throw const ApiException.connection();
    } on http.ClientException {
      throw const ApiException.connection();
    } on TimeoutException {
      throw const ApiException.connection();
    }
    final text = utf8.decode(response.bodyBytes);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return text.isEmpty ? null : jsonDecode(text);
    }
    throw ApiException(_backendMessage(text), statusCode: response.statusCode);
  }

  static String _backendMessage(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic> && decoded['message'] is String) {
        return decoded['message'] as String;
      }
    } on FormatException {
      // Cuerpo que no es JSON: se usa el texto generico de la pantalla.
    }
    return '';
  }
}
