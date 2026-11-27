import 'dart:async';
import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../../../core/common/result.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/session/session_storage.dart';
import 'pending_sanitary_store.dart';

/// US-35: sent = el backend lo guardo (201, o 200 si ya lo tenia); queued = quedo en el dispositivo y se enviara solo.
enum SanitarySaveResult { sent, queued }

/// Resultado de un envio. transient (sin conexion, timeout, 408, 429, 5xx) se reintenta; session (401/403, o la sesion
/// cambio) espera a que vuelva el mismo usuario; rejected (otro 4xx) no se reenvia solo.
sealed class _Outcome {
  const _Outcome();
}

final class _Sent extends _Outcome {
  const _Sent();
}

final class _Transient extends _Outcome {
  const _Transient(this.error);
  final String error;
}

final class _Session extends _Outcome {
  const _Session(this.error);
  final String error;
}

final class _Rejected extends _Outcome {
  const _Rejected(this.error, this.message);
  final String error;
  final String message;
}

/// US-35: cola offline de registrar (US-11) y programar (US-13) eventos sanitarios. Independiente de los widgets.
///
/// - [save] guarda la operacion en SQLite ANTES de enviarla y la envia una vez: si la app muere a mitad del POST, la
///   fila sigue ahi y se reenvia con el mismo clientRequestId (el backend devuelve 200 si ya la habia creado).
/// - [sync] envia las PENDING del usuario de la sesion, en orden de creacion. Una sola ejecucion a la vez: las llamadas
///   durante una ejecucion se encadenan detras.
/// - Se dispara al iniciar ([start]), al volver la conectividad ([reconnections]), al guardar y con reintentos con
///   backoff exponencial ([retryDelay]) tras un error transitorio. Solo mientras la app esta viva: no hay envio en
///   segundo plano con la app cerrada.
/// - Aislamiento: cada operacion lleva el id de IAM del usuario y solo se envia con la sesion de ese mismo usuario.
///
/// Para US-40: [operations] lista PENDING y FAILED con su ultimo error, [retry] reenvia una FAILED con el mismo
/// clientRequestId, y los cambios se observan como [ChangeNotifier] ([syncing], cola modificada).
class SanitarySyncService extends ChangeNotifier {
  SanitarySyncService({
    required PendingSanitaryStore store,
    required ApiClient api,
    required SessionStorage session,
    Stream<void>? reconnections,
    Duration Function(int failures)? retryDelay,
    DateTime Function()? now,
  })  : _store = store, // ignore: prefer_initializing_formals
        _api = api, // ignore: prefer_initializing_formals
        _session = session, // ignore: prefer_initializing_formals
        _reconnections = reconnections, // ignore: prefer_initializing_formals
        _retryDelay = retryDelay ?? defaultRetryDelay,
        _now = now ?? DateTime.now;

  final PendingSanitaryStore _store;
  final ApiClient _api;
  final SessionStorage _session;
  final Stream<void>? _reconnections;
  final Duration Function(int failures) _retryDelay;
  final DateTime Function() _now;

  StreamSubscription<void>? _subscription;
  Timer? _retryTimer;
  int _failures = 0;
  Future<void> _lock = Future.value();
  Future<void>? _running;
  bool _again = false;
  bool _disposed = false;

  /// 30 s, 1 min, 2 min... hasta 15 min.
  static Duration defaultRetryDelay(int failures) => Duration(seconds: min(30 * pow(2, failures - 1).toInt(), 900));

  bool get syncing => _running != null;

  /// Id de IAM del usuario con sesion; null sin sesion.
  String? get userId => _user()?.id;

  ({String id, String token})? _user() {
    final id = _session.userId;
    final token = _session.token;
    if (id == null || id.isEmpty || token == null || token.isEmpty) return null;
    return (id: id, token: token);
  }

  bool _isCurrent(({String id, String token}) user) => _session.userId == user.id && _session.token == user.token;

  /// Escucha la conectividad y envia lo que haya quedado pendiente de una ejecucion anterior.
  void start() {
    _subscription ??= _reconnections?.listen((_) {
      _failures = 0;
      unawaited(sync());
    });
    unawaited(sync());
  }

  /// Al cerrar sesion: cancela el reintento programado. Las operaciones del usuario quedan guardadas y se envian
  /// cuando ese mismo usuario vuelva a iniciar sesion.
  void suspend() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _failures = 0;
  }

  /// Guarda [request] y lo intenta enviar. Success(sent) si el backend lo guardo, Success(queued) si quedo en la cola
  /// (sin conexion o backend caido), Failure con el message del backend si lo rechazo (400, 409...): el formulario lo
  /// muestra con los datos intactos y la fila se borra, porque el usuario la corrige ahi mismo.
  ///
  /// Sin usuario identificado o si no se puede escribir la base, se envia sin cola como antes de US-35 (un error de
  /// conexion se informa como tal: nada quedo guardado).
  Future<Result<SanitarySaveResult>> save(SanitaryRequest request) async {
    final user = _user();
    if (user == null) return _sendWithoutQueue(request);
    try {
      await _store.insert(PendingSanitaryOperation(request: request, userId: user.id, createdAt: _now()));
    } catch (e) {
      debugPrint('US-35: no se pudo guardar la operacion local: $e');
      return _sendWithoutQueue(request);
    }
    _notify();
    return _locked(() async {
      // Una sincronizacion que tomo el turno antes pudo enviarla ya: si la fila no esta, el backend la confirmo.
      try {
        if (await _store.find(request.clientRequestId) == null) return const Success(SanitarySaveResult.sent);
      } catch (_) {
        // Sin poder leer la base se envia igual: el mismo id no duplica el evento.
      }
      final outcome = await _send(request, user);
      try {
        switch (outcome) {
          case _Sent():
            await _store.delete(request.clientRequestId);
            _failures = 0;
            _notify();
            unawaited(sync()); // por si quedaban otras de antes
            return const Success(SanitarySaveResult.sent);
          case _Rejected(:final message):
            await _store.delete(request.clientRequestId);
            _notify();
            return Failure(message);
          case _Transient(:final error):
            await _store.recordError(request.clientRequestId, error);
            _scheduleRetry();
            return const Success(SanitarySaveResult.queued);
          case _Session(:final error):
            await _store.recordError(request.clientRequestId, error);
            return const Success(SanitarySaveResult.queued);
        }
      } catch (e) {
        // La fila no se pudo actualizar: sigue PENDING y el reenvio con el mismo id no duplica nada.
        debugPrint('US-35: no se pudo actualizar la operacion local: $e');
        return outcome is _Sent ? const Success(SanitarySaveResult.sent) : const Success(SanitarySaveResult.queued);
      }
    });
  }

  Future<Result<SanitarySaveResult>> _sendWithoutQueue(SanitaryRequest request) async {
    try {
      await _api.post(request.path, body: request.body);
      return const Success(SanitarySaveResult.sent);
    } on FormatException {
      return const Success(SanitarySaveResult.sent); // 2xx con un cuerpo que no es JSON: el backend ya lo guardo
    } on ApiException catch (e) {
      return Failure(e.message, isConnectionError: e.isConnectionError);
    }
  }

  /// Envia las PENDING del usuario de la sesion. Si ya hay una ejecucion en curso, devuelve esa y la repite al terminar
  /// para tomar lo que se haya agregado mientras tanto.
  Future<void> sync() {
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    final run = _locked(() async {
      do {
        _again = false;
        await _syncOnce();
      } while (_again && !_disposed);
    });
    _running = run;
    _notify();
    return run.whenComplete(() {
      _running = null;
      _notify();
    });
  }

  Future<void> _syncOnce() async {
    final user = _user();
    if (user == null) return;
    try {
      for (final operation in await _store.pending(user.id)) {
        final outcome = await _send(operation.request, user);
        switch (outcome) {
          case _Sent():
            await _store.delete(operation.clientRequestId);
          case _Rejected(:final error):
            await _store.markFailed(operation.clientRequestId, error);
          case _Transient(:final error):
            await _store.recordError(operation.clientRequestId, error);
            _scheduleRetry();
            return; // sin red o backend caido: el resto fallaria igual
          case _Session(:final error):
            await _store.recordError(operation.clientRequestId, error);
            return; // espera a que vuelva la sesion de este usuario
        }
        _notify();
      }
      _failures = 0;
    } catch (e) {
      // Fallo de la base local: lo no confirmado sigue PENDING y se reintenta.
      debugPrint('US-35: error de la cola local al sincronizar: $e');
      _scheduleRetry();
    }
  }

  Future<_Outcome> _send(SanitaryRequest request, ({String id, String token}) user) async {
    // Se comprueba justo antes de enviar (sin await entre medio): ApiClient pone el token de la sesion actual.
    if (_disposed || !_isCurrent(user)) return const _Session('SESSION');
    try {
      await _api.post(request.path, body: request.body);
      return const _Sent();
    } on FormatException {
      return const _Sent(); // ApiClient solo decodifica el cuerpo de un 2xx
    } on ApiException catch (e) {
      final code = e.statusCode;
      if (code == null) return const _Transient('CONNECTION');
      final error = e.message.isEmpty ? 'HTTP $code' : e.message;
      if (code == 408 || code == 429 || code >= 500) return _Transient(error);
      if (code == 401 || code == 403) return _Session(error);
      return _Rejected(error, e.message);
    }
  }

  void _scheduleRetry() {
    if (_disposed) return;
    _failures++;
    _retryTimer?.cancel();
    _retryTimer = Timer(_retryDelay(_failures), () => unawaited(sync()));
  }

  /// PENDING y FAILED del usuario de la sesion, en orden de creacion; vacia sin sesion.
  Future<List<PendingSanitaryOperation>> operations() async {
    final user = _user();
    return user == null ? const [] : _store.all(user.id);
  }

  /// US-40: vuelve a PENDING una operacion del usuario de la sesion y sincroniza, con el mismo clientRequestId.
  Future<void> retry(String clientRequestId) async {
    final user = _user();
    if (user == null || !await _store.retry(user.id, clientRequestId)) return;
    _failures = 0;
    _notify();
    await sync();
  }

  Future<T> _locked<T>(Future<T> Function() action) {
    final result = _lock.then((_) => action());
    _lock = result.then((_) {}, onError: (_) {});
    return result;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
