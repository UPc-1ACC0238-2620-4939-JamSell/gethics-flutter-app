import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gethics/app.dart';
import 'package:gethics/core/common/result.dart';
import 'package:gethics/core/di/app_dependencies.dart';
import 'package:gethics/core/network/api_client.dart';
import 'package:gethics/core/session/session_storage.dart';
import 'package:gethics/features/sanitary/data/pending_sanitary_store.dart';
import 'package:gethics/features/sanitary/data/sanitary_repository.dart';
import 'package:gethics/features/sanitary/data/sanitary_sync_service.dart';
import 'package:gethics/features/sanitary/domain/animal_option.dart';
import 'package:gethics/features/sanitary/domain/upcoming_event.dart';
import 'package:gethics/features/sanitary/presentation/register_event_page.dart';
import 'package:gethics/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'sanitary_repository_test.dart' show animalsJson;

/// Backend con la idempotencia de US-35: un clientRequestId nuevo crea (201), repetido con el mismo cuerpo devuelve el
/// existente (200) y con otro cuerpo es 409. [override] simula red caida, timeouts o rechazos.
class IdempotentBackend {
  final created = <String, String>{};
  final requests = <http.Request>[];
  Future<http.Response> Function(http.Request)? override;

  Future<http.Response> handle(http.Request request) async {
    if (request.method == 'GET') return http.Response(animalsJson, 200);
    requests.add(request);
    if (override != null) return override!(request);
    return answer(request);
  }

  http.Response answer(http.Request request) {
    final id = jsonDecode(request.body)['clientRequestId'] as String;
    final key = '${request.url.path} ${request.body}';
    final existing = created[id];
    if (existing == null) {
      created[id] = key;
      return http.Response('{"id":"ev-$id"}', 201);
    }
    return existing == key ? http.Response('{"id":"ev-$id"}', 200) : http.Response('{"message":"Otro evento."}', 409);
  }

  List<String> get ids => [for (final r in requests) jsonDecode(r.body)['clientRequestId'] as String];
  List<String?> get tokens => [for (final r in requests) r.headers['authorization']];
}

Future<http.Response> offline(http.Request _) async => throw const SocketException('sin red');

Future<SessionStorage> signedIn({String token = 't7', String userId = '7'}) async {
  SharedPreferences.setMockInitialValues({'session.token': token, 'session.userId': userId, 'session.name': 'Ana'});
  return SessionStorage(await SharedPreferences.getInstance());
}

ApiClient apiFor(IdempotentBackend backend, SessionStorage session, {Duration timeout = const Duration(seconds: 5)}) =>
    ApiClient(
      baseUrl: 'https://api.example.com',
      client: MockClient(backend.handle),
      tokenProvider: () => session.token,
      timeout: timeout,
    );

SanitaryRequest request(String id, {String animal = 'a1', String? description}) => SanitaryRequest(
      operation: SanitaryOperation.register,
      animalId: animal,
      type: SanitaryEventType.checkup,
      date: '2026-11-26T00:00:00',
      description: description,
      clientRequestId: id,
    );

PendingSanitaryOperation pending(String id, {String userId = '7', int createdAt = 1}) => PendingSanitaryOperation(
    request: request(id), userId: userId, createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt));

void main() {
  sqfliteFfiInit();

  late Directory dir;
  final opened = <PendingSanitaryStore>[];
  final services = <SanitarySyncService>[];

  Future<PendingSanitaryStore> openStore() async {
    final store = await PendingSanitaryStore.open(factory: databaseFactoryFfi, path: '${dir.path}/gethics.db');
    opened.add(store);
    return store;
  }

  SanitarySyncService service(
    PendingSanitaryStore store,
    ApiClient api,
    SessionStorage session, {
    Stream<void>? reconnections,
    Duration Function(int)? retryDelay,
  }) {
    final sync = SanitarySyncService(
      store: store,
      api: api,
      session: session,
      reconnections: reconnections,
      retryDelay: retryDelay ?? (_) => const Duration(hours: 1),
    );
    services.add(sync);
    return sync;
  }

  setUp(() async => dir = await Directory.systemTemp.createTemp('us35_'));

  tearDown(() async {
    for (final sync in services) {
      try {
        sync.dispose();
      } catch (_) {} // algunas pruebas ya la cerraron
    }
    services.clear();
    for (final store in opened) {
      try {
        await store.close();
      } catch (_) {}
    }
    opened.clear();
    await dir.delete(recursive: true);
  });

  group('persistencia', () {
    test('guarda la operacion completa y la devuelve en orden de creacion', () async {
      final store = await openStore();
      await store.insert(PendingSanitaryOperation(
        request: const SanitaryRequest(
          operation: SanitaryOperation.schedule,
          animalId: 'a2',
          type: SanitaryEventType.vaccination,
          date: '2026-12-01',
          description: 'Refuerzo',
          clientRequestId: 'id-2',
        ),
        userId: '7',
        createdAt: DateTime.fromMillisecondsSinceEpoch(20),
      ));
      await store.insert(pending('id-1', createdAt: 10));
      await store.insert(pending('id-3', createdAt: 20)); // mismo milisegundo que id-2: desempata el orden de insercion

      final ops = await store.pending('7');
      expect(ops.map((o) => o.clientRequestId), ['id-1', 'id-2', 'id-3']);
      final scheduled = ops[1];
      expect(scheduled.request.operation, SanitaryOperation.schedule);
      expect(scheduled.request.animalId, 'a2');
      expect(scheduled.request.type, SanitaryEventType.vaccination);
      expect(scheduled.request.date, '2026-12-01');
      expect(scheduled.request.description, 'Refuerzo');
      expect(scheduled.userId, '7');
      expect(scheduled.createdAt, DateTime.fromMillisecondsSinceEpoch(20));
      expect(scheduled.status, PendingStatus.pending);
      expect(scheduled.lastError, isNull);
      expect(scheduled.request.path, 'api/v1/animals/a2/sanitary-events/scheduled');
      expect(scheduled.request.body,
          {'type': 'VACCINATION', 'scheduledDate': '2026-12-01', 'description': 'Refuerzo', 'clientRequestId': 'id-2'});
    });

    test('las operaciones sobreviven a cerrar y volver a abrir la base', () async {
      final first = await openStore();
      await first.insert(pending('id-1'));
      await first.close();

      final reopened = await openStore();
      expect((await reopened.pending('7')).single.clientRequestId, 'id-1');
    });

    test('un clientRequestId repetido se rechaza y no reemplaza la operacion original', () async {
      final store = await openStore();
      await store.insert(pending('id-1'));

      await expectLater(
        store.insert(PendingSanitaryOperation(
            request: request('id-1', animal: 'otro'), userId: '7', createdAt: DateTime.fromMillisecondsSinceEpoch(5))),
        throwsA(isA<DatabaseException>()),
      );
      expect((await store.pending('7')).single.request.animalId, 'a1');
    });

    test('cada usuario solo ve y reintenta sus operaciones', () async {
      final store = await openStore();
      await store.insert(pending('de-7'));
      await store.insert(pending('de-8', userId: '8'));
      await store.markFailed('de-8', 'x');

      expect((await store.pending('7')).map((o) => o.clientRequestId), ['de-7']);
      expect((await store.all('8')).map((o) => o.clientRequestId), ['de-8']);
      expect(await store.retry('7', 'de-8'), isFalse);
      expect((await store.all('8')).single.status, PendingStatus.failed);
    });

    test('una FAILED se conserva con su error y un reintento manual la vuelve PENDING con el mismo id', () async {
      final store = await openStore();
      await store.insert(pending('id-1'));
      await store.markFailed('id-1', 'El animal no existe.');

      expect(await store.pending('7'), isEmpty);
      final failed = (await store.all('7')).single;
      expect(failed.status, PendingStatus.failed);
      expect(failed.lastError, 'El animal no existe.');

      expect(await store.retry('7', 'id-1'), isTrue);
      expect((await store.pending('7')).single.clientRequestId, 'id-1');
    });
  });

  group('guardar (registro y programacion)', () {
    test('con conexion: 201, queda sincronizado, la cola queda vacia y el cuerpo es el del contrato', () async {
      final session = await signedIn();
      final backend = IdempotentBackend();
      final store = await openStore();
      final repo = SanitaryRepository(apiFor(backend, session), offline: service(store, apiFor(backend, session), session));

      final result = await repo.registerEvent(
        animalId: 'a1',
        type: SanitaryEventType.treatment,
        occurredAt: DateTime(2026, 11, 20, 15),
        description: 'Antibiotico',
        clientRequestId: 'id-1',
      );

      expect(result, isA<Success<SanitarySaveResult>>().having((s) => s.data, 'data', SanitarySaveResult.sent));
      expect(await store.all('7'), isEmpty);
      final sent = backend.requests.single;
      expect(sent.url.path, '/api/v1/animals/a1/sanitary-events');
      expect(sent.headers['authorization'], 'Bearer t7');
      expect(jsonDecode(sent.body),
          {'type': 'TREATMENT', 'occurredAt': '2026-11-20T00:00:00', 'description': 'Antibiotico', 'clientRequestId': 'id-1'});
    });

    test('un 200 (el backend ya lo tenia) tambien cuenta como sincronizado', () async {
      final session = await signedIn();
      final backend = IdempotentBackend()..created['id-1'] = '/api/v1/animals/a1/sanitary-events ${jsonEncode(request('id-1').body)}';
      final store = await openStore();
      final sync = service(store, apiFor(backend, session), session);

      expect(await sync.save(request('id-1')), isA<Success<SanitarySaveResult>>().having((s) => s.data, 'data', SanitarySaveResult.sent));
      expect(await store.all('7'), isEmpty);
      expect(backend.created, hasLength(1));
    });

    test('sin conexion: queda PENDING con el mismo id y se envia al volver la conexion', () async {
      final session = await signedIn();
      final backend = IdempotentBackend()..override = offline;
      final store = await openStore();
      final sync = service(store, apiFor(backend, session), session);

      final result = await sync.save(request('id-1', description: 'Control'));

      expect(result, isA<Success<SanitarySaveResult>>().having((s) => s.data, 'data', SanitarySaveResult.queued));
      final queued = (await store.pending('7')).single;
      expect(queued.lastError, 'CONNECTION');
      expect(queued.request.description, 'Control');

      backend.override = null;
      await sync.sync();
      expect(await store.all('7'), isEmpty);
      expect(backend.ids, ['id-1', 'id-1']);
      expect(backend.created.keys, ['id-1']);
    });

    test('programar una vacuna sin conexion tambien queda en la cola', () async {
      final session = await signedIn();
      final backend = IdempotentBackend()..override = offline;
      final store = await openStore();
      final repo = SanitaryRepository(apiFor(backend, session), offline: service(store, apiFor(backend, session), session));

      final result = await repo.scheduleVaccination(
          animalId: 'a1', scheduledDate: DateTime(2026, 12, 3), description: 'Aftosa', clientRequestId: 'vac-1');

      expect((result as Success<SanitarySaveResult>).data, SanitarySaveResult.queued);
      final queued = (await store.pending('7')).single;
      expect(queued.request.operation, SanitaryOperation.schedule);
      expect(queued.request.body,
          {'type': 'VACCINATION', 'scheduledDate': '2026-12-03', 'description': 'Aftosa', 'clientRequestId': 'vac-1'});
    });

    test('timeout despues de que el backend lo guardo: el reintento con el mismo id no duplica el evento', () async {
      final session = await signedIn();
      final backend = IdempotentBackend();
      backend.override = (r) async {
        backend.answer(r); // el backend lo guarda...
        await Future<void>.delayed(const Duration(milliseconds: 300)); // ...pero la respuesta no llega a tiempo
        return http.Response('{}', 201);
      };
      final store = await openStore();
      final sync = service(store, apiFor(backend, session, timeout: const Duration(milliseconds: 50)), session);

      expect((await sync.save(request('id-1')) as Success<SanitarySaveResult>).data, SanitarySaveResult.queued);

      backend.override = null;
      await sync.sync();
      expect(await store.all('7'), isEmpty);
      expect(backend.ids, ['id-1', 'id-1']);
      expect(backend.created, hasLength(1)); // un solo evento en el servidor
    });

    test('error transitorio (503) queda en la cola; rechazo definitivo (400) vuelve al formulario sin dejar fila', () async {
      final session = await signedIn();
      final backend = IdempotentBackend()..override = (_) async => http.Response('{"message":"Mantenimiento"}', 503);
      final store = await openStore();
      final sync = service(store, apiFor(backend, session), session);

      expect((await sync.save(request('id-1')) as Success<SanitarySaveResult>).data, SanitarySaveResult.queued);
      expect((await store.pending('7')).single.lastError, 'Mantenimiento');

      backend.override = (_) async => http.Response('{"message":"La fecha no puede ser posterior a hoy."}', 400);
      final rejected = await sync.save(request('id-2'));
      expect(rejected, isA<Failure<SanitarySaveResult>>()
          .having((f) => f.message, 'message', 'La fecha no puede ser posterior a hoy.')
          .having((f) => f.isConnectionError, 'isConnectionError', false));
      expect((await store.all('7')).map((o) => o.clientRequestId), ['id-1']);
    });

    test('una sincronizacion simultanea al guardado no envia dos veces la misma operacion', () async {
      // El doble toque del formulario lo evita el view model (register_event_test); aqui, la cola: si la sincronizacion
      // (p. ej. por volver la red) toma el turno y envia la fila, el guardado ve que ya no esta y no la reenvia.
      final session = await signedIn();
      final gate = Completer<void>();
      final backend = IdempotentBackend();
      backend.override = (r) async {
        await gate.future;
        return backend.answer(r);
      };
      final store = await openStore();
      final sync = service(store, apiFor(backend, session), session);

      final saving = sync.save(request('id-1'));
      await pumpEventQueue();
      final syncing = sync.sync();
      gate.complete();
      await saving;
      await syncing;

      expect(backend.ids, ['id-1']);
      expect(await store.all('7'), isEmpty);
    });

    test('sesion sin id de usuario (anterior a US-35): se envia sin cola y sin conexion informa el error', () async {
      SharedPreferences.setMockInitialValues({'session.token': 't7'});
      final session = SessionStorage(await SharedPreferences.getInstance());
      final backend = IdempotentBackend()..override = offline;
      final store = await openStore();
      final sync = service(store, apiFor(backend, session), session);

      final result = await sync.save(request('id-1'));

      expect(result, isA<Failure<SanitarySaveResult>>().having((f) => f.isConnectionError, 'isConnectionError', true));
      expect(await store.all('7'), isEmpty);
    });

    test('si la base local falla al guardar, se envia directo: con red se registra y sin red no promete nada', () async {
      final session = await signedIn();
      final backend = IdempotentBackend();
      final store = await openStore();
      final sync = service(store, apiFor(backend, session), session);
      await store.close();

      expect((await sync.save(request('id-1')) as Success<SanitarySaveResult>).data, SanitarySaveResult.sent);
      backend.override = offline;
      expect(await sync.save(request('id-2')),
          isA<Failure<SanitarySaveResult>>().having((f) => f.isConnectionError, 'isConnectionError', true));
    });

    test('si la base falla despues de un 201, la fila queda y el reenvio recibe 200 sin duplicar', () async {
      final session = await signedIn();
      final backend = IdempotentBackend();
      final store = await openStore();
      backend.override = (r) async {
        await store.close(); // la base deja de responder justo antes de borrar la fila
        return backend.answer(r);
      };
      final sync = service(store, apiFor(backend, session), session);

      expect((await sync.save(request('id-1')) as Success<SanitarySaveResult>).data, SanitarySaveResult.sent);

      // Al reiniciar la app la operacion sigue ahi y se reenvia con el mismo id.
      backend.override = null;
      final restarted = await openStore();
      expect((await restarted.pending('7')).single.clientRequestId, 'id-1');
      await service(restarted, apiFor(backend, session), session).sync();
      expect(await restarted.all('7'), isEmpty);
      expect(backend.ids, ['id-1', 'id-1']);
      expect(backend.created, hasLength(1));
    });
  });

  group('sincronizacion', () {
    Future<(PendingSanitaryStore, IdempotentBackend, SessionStorage)> queued(List<String> ids) async {
      final session = await signedIn();
      final backend = IdempotentBackend()..override = offline;
      final store = await openStore();
      final sync = service(store, apiFor(backend, session), session);
      for (final id in ids) {
        await sync.save(request(id));
      }
      sync.dispose();
      backend
        ..override = null
        ..requests.clear();
      return (store, backend, session);
    }

    test('al iniciar la app envia en orden lo que quedo pendiente y borra solo lo confirmado', () async {
      final (store, backend, session) = await queued(['id-1', 'id-2', 'id-3']);

      final sync = service(store, apiFor(backend, session), session)..start();
      await sync.sync();

      expect(backend.ids, ['id-1', 'id-2', 'id-3']);
      expect(await store.all('7'), isEmpty);
    });

    test('volver la conexion dispara la sincronizacion', () async {
      final (store, backend, session) = await queued(['id-1']);
      final reconnections = StreamController<void>();
      final sync = service(store, apiFor(backend, session), session, reconnections: reconnections.stream);
      backend.override = offline;
      sync.start();
      await sync.sync();
      expect(await store.pending('7'), hasLength(1));

      backend.override = null;
      reconnections.add(null);
      await pumpEventQueue();
      await sync.sync();

      expect(await store.all('7'), isEmpty);
      expect(backend.ids.toSet(), {'id-1'});
      await reconnections.close();
    });

    test('un rechazo definitivo queda FAILED con su error y no bloquea a las siguientes', () async {
      final (store, backend, session) = await queued(['id-1', 'id-2']);
      backend.override = (r) async => jsonDecode(r.body)['clientRequestId'] == 'id-1'
          ? http.Response('{"message":"El clientRequestId ya se uso con datos distintos."}', 409)
          : backend.answer(r);

      await service(store, apiFor(backend, session), session).sync();

      final all = await store.all('7');
      expect(all.single.clientRequestId, 'id-1');
      expect(all.single.status, PendingStatus.failed);
      expect(all.single.lastError, 'El clientRequestId ya se uso con datos distintos.');
      expect(backend.created.keys, ['id-2']);
    });

    test('un error transitorio corta la ejecucion, conserva el orden y reintenta solo con backoff y el mismo id', () async {
      final (store, backend, session) = await queued(['id-1', 'id-2']);
      var failures = 0;
      backend.override = (r) async {
        if (failures++ == 0) return http.Response('', 500);
        return backend.answer(r);
      };
      final delays = <int>[];
      final sync = service(store, apiFor(backend, session), session, retryDelay: (n) {
        delays.add(n);
        return const Duration(milliseconds: 20);
      });

      await sync.sync();
      expect(backend.ids, ['id-1']); // id-2 no se intento
      expect((await store.pending('7')).first.lastError, 'HTTP 500');

      await Future<void>.delayed(const Duration(milliseconds: 100));
      await sync.sync();
      expect(delays.first, 1);
      expect(backend.ids, ['id-1', 'id-1', 'id-2']);
      expect(await store.all('7'), isEmpty);
    });

    test('dos sincronizaciones a la vez no envian dos veces la misma operacion', () async {
      final (store, backend, session) = await queued(['id-1', 'id-2']);
      final gate = Completer<void>();
      backend.override = (r) async {
        await gate.future;
        return backend.answer(r);
      };
      final sync = service(store, apiFor(backend, session), session);

      final first = sync.sync();
      final second = sync.sync();
      expect(sync.syncing, isTrue);
      gate.complete();
      await Future.wait([first, second]);

      expect(backend.ids, ['id-1', 'id-2']);
      expect(sync.syncing, isFalse);
    });

    test('si cambia el usuario durante la sincronizacion, no se envia nada mas con la sesion nueva', () async {
      final (store, backend, session) = await queued(['id-1', 'id-2']);
      backend.override = (r) async {
        await session.save(token: 't8', userId: '8', role: 'VETERINARIO', name: 'Beto'); // otro usuario inicia sesion
        return backend.answer(r);
      };
      final sync = service(store, apiFor(backend, session), session);

      await sync.sync();
      expect(backend.ids, ['id-1']);
      expect(backend.tokens, ['Bearer t7']);
      expect((await store.pending('7')).map((o) => o.clientRequestId), ['id-2']);

      // Con la sesion del usuario 8 las operaciones del 7 no se envian.
      backend.override = null;
      await sync.sync();
      expect(backend.ids, ['id-1']);

      // Vuelve el usuario 7 (otro token): ahora si, con su sesion y el mismo id.
      await session.save(token: 't7b', userId: '7', role: 'VETERINARIO', name: 'Ana');
      await sync.sync();
      expect(backend.ids, ['id-1', 'id-2']);
      expect(backend.tokens.last, 'Bearer t7b');
      expect(await store.all('7'), isEmpty);
    });

    test('al cerrar sesion se conservan las pendientes y no se envian hasta que vuelve el mismo usuario', () async {
      final (store, backend, session) = await queued(['id-1']);
      final sync = service(store, apiFor(backend, session), session);

      sync.suspend();
      await session.clear();
      await sync.sync();
      expect(backend.requests, isEmpty);
      expect(await store.pending('7'), hasLength(1));
      expect(sync.userId, isNull);

      await session.save(token: 't7', userId: '7', role: 'VETERINARIO', name: 'Ana');
      await sync.sync();
      expect(backend.ids, ['id-1']);
      expect(await store.all('7'), isEmpty);
    });

    test('401/403 no marca la operacion como rechazada ni la reintenta sola', () async {
      final (store, backend, session) = await queued(['id-1']);
      backend.override = (_) async => http.Response('', 401);
      final sync = service(store, apiFor(backend, session), session, retryDelay: (_) => const Duration(milliseconds: 10));

      await sync.sync();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(backend.requests, hasLength(1));
      final op = (await store.pending('7')).single;
      expect(op.status, PendingStatus.pending);
      expect(op.lastError, 'HTTP 401');
    });

    test('US-40: lista PENDING y FAILED y un reintento manual reenvia la FAILED con el mismo id', () async {
      final (store, backend, session) = await queued(['id-1']);
      backend.override = (_) async => http.Response('{"message":"Animal invalido."}', 400);
      final sync = service(store, apiFor(backend, session), session);
      await sync.sync();
      expect((await sync.operations()).single.status, PendingStatus.failed);

      backend.override = null;
      var notified = 0;
      sync.addListener(() => notified++);
      await sync.retry('id-1');

      expect(backend.ids, ['id-1', 'id-1']);
      expect(await sync.operations(), isEmpty);
      expect(notified, greaterThan(0));
    });
  });

  test('sin conexion el formulario usa la ultima lista de animales del mismo usuario', () async {
    final session = await signedIn();
    var online = true;
    final api = ApiClient(
      baseUrl: 'https://api.example.com',
      client: MockClient((_) async => online ? http.Response(animalsJson, 200) : throw const SocketException('x')),
      tokenProvider: () => session.token,
    );
    final repo = SanitaryRepository(api, offline: service(await openStore(), api, session));

    await repo.getAnimals();
    online = false;
    final cached = await repo.getAnimals();
    expect((cached as Success<List<AnimalOption>>).data.map((a) => a.id), ['a1', 'a2']);

    await session.save(token: 't8', userId: '8', role: 'VETERINARIO', name: 'Beto');
    expect(await repo.getAnimals(), isA<Failure<List<AnimalOption>>>().having((f) => f.isConnectionError, 'c', true));
  });

  group('pantalla', () {
    for (final (locale, message) in [
      ('es', 'Evento guardado sin conexión. Se sincronizará cuando vuelva la conexión.'),
      ('en', 'Event saved offline. It will sync when the connection is restored.'),
    ]) {
      testWidgets('sin conexion cierra el formulario con queued y avisa que se sincronizara ($locale)', (tester) async {
        final session = await signedIn();
        final backend = IdempotentBackend()..override = offline;
        final store = await PendingSanitaryStore.open(factory: databaseFactoryFfiNoIsolate, path: inMemoryDatabasePath);
        opened.add(store);
        final sync = service(store, apiFor(backend, session), session);
        final repo = SanitaryRepository(apiFor(backend, session), offline: sync);
        SanitarySaveResult? result;

        await tester.pumpWidget(MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  final l10n = AppLocalizations.of(context);
                  final messenger = ScaffoldMessenger.of(context);
                  result = await Navigator.of(context)
                      .push(registerEventRoute(repo, animal: const AnimalOption(id: 'a1', label: 'Lola')));
                  final text = saveResultMessage(l10n, result, sentMessage: l10n.registerEventSuccess);
                  if (text != null) messenger.showSnackBar(SnackBar(content: Text(text)));
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('abrir'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('register-type')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(locale == 'es' ? 'Chequeo' : 'Checkup').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('register-submit')));
        await tester.tap(find.byKey(const Key('register-submit')));
        await tester.pumpAndSettle();

        expect(result, SanitarySaveResult.queued);
        expect(find.text(message), findsOneWidget);
        expect(find.text(locale == 'es' ? 'Evento sanitario registrado.' : 'Sanitary event registered.'), findsNothing);
        expect(find.byKey(const Key('register-submit')), findsNothing);
        expect(await store.pending('7'), hasLength(1));
        sync.dispose(); // cancela el reintento programado antes de que termine la prueba
      });
    }

    testWidgets('desde Calendario: con red confirma el registro y sin red avisa del guardado offline', (tester) async {
      SharedPreferences.setMockInitialValues(
          {'session.token': 't7', 'session.userId': '7', 'session.role': 'VETERINARIO', 'session.name': 'Ana'});
      final backend = IdempotentBackend();
      var network = true;
      final store = await PendingSanitaryStore.open(factory: databaseFactoryFfiNoIsolate, path: inMemoryDatabasePath);
      opened.add(store);
      final dependencies = await AppDependencies.create(
        client: MockClient((r) async {
          if (!network) throw const SocketException('sin red');
          return r.url.path.endsWith('upcoming') || r.url.path.endsWith('sanitary-calendar')
              ? http.Response('{"events":[],"message":"Sin eventos."}', 200)
              : backend.handle(r);
        }),
        store: store,
        reconnections: const Stream.empty(),
      );
      await tester.pumpWidget(GethicsApp(dependencies: dependencies));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.calendar_month_outlined));
      await tester.pumpAndSettle();

      Future<void> register() async {
        await tester.tap(find.text('Register event'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('register-animal')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Lola').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('register-type')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Checkup').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('register-submit')));
        await tester.tap(find.byKey(const Key('register-submit')));
        await tester.pumpAndSettle();
      }

      await register();
      expect(find.text('Sanitary event registered.'), findsOneWidget);
      expect(backend.created, hasLength(1));
      ScaffoldMessenger.of(tester.element(find.byType(NavigationBar))).removeCurrentSnackBar();
      await tester.pumpAndSettle();

      // Sin red: la lista de animales sale de la ultima consulta y el evento queda en la cola.
      network = false;
      await register();
      expect(find.text('Event saved offline. It will sync when the connection is restored.'), findsOneWidget);
      expect(find.text('Sanitary event registered.'), findsNothing);
      expect(await store.pending('7'), hasLength(1));
      dependencies.sanitarySync!.dispose();
    });
  });
}
