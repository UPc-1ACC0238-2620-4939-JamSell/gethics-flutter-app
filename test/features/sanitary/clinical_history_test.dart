import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gethics/app.dart';
import 'package:gethics/core/common/result.dart';
import 'package:gethics/core/di/app_dependencies.dart';
import 'package:gethics/core/network/api_client.dart';
import 'package:gethics/features/sanitary/data/sanitary_repository.dart';
import 'package:gethics/features/sanitary/domain/animal_option.dart';
import 'package:gethics/features/sanitary/domain/clinical_history.dart';
import 'package:gethics/features/sanitary/domain/upcoming_event.dart';
import 'package:gethics/features/sanitary/presentation/clinical_history_page.dart';
import 'package:gethics/features/sanitary/presentation/clinical_history_view_model.dart';
import 'package:gethics/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sanitary_repository_test.dart' show animalsJson;

/// Respuesta con un evento de cada estado, en el orden cronologico ascendente del backend, y casos con datos nulos.
const historyJson = '''
{"animalId":"a1","message":null,"events":[
 {"id":"e1","type":"TREATMENT","status":"COMPLETED","occurredAt":"2026-10-05T08:30:00","scheduledDate":null,"description":"Antibiotico"},
 {"id":"e2","type":"VACCINATION","status":"COMPLETED","occurredAt":"2026-11-20T00:00:00","scheduledDate":"2026-11-18","description":"  "},
 {"id":"e3","type":"CHECKUP","status":"CANCELLED","occurredAt":null,"scheduledDate":"2026-11-25","description":"Control cancelado"},
 {"id":"e4","type":"DISEASE","status":"SCHEDULED","occurredAt":null,"scheduledDate":"2026-12-18","description":null},
 {"id":"e5","type":"NUEVO","status":"RARO","occurredAt":null,"scheduledDate":null,"description":null},
 {"id":"e6","type":"OTHER","status":"COMPLETED","occurredAt":null,"scheduledDate":"2026-12-01","description":null}]}''';

const emptyJson = '{"animalId":"a1","events":[],"message":"Sin registros."}';

/// Backend simulado: animales, historial (configurable) y registro de eventos (el evento queda en el historial).
class FakeBackend {
  FakeBackend({String? history}) : history = history ?? historyJson;

  String history;
  Future<http.Response> Function(http.Request)? historyHandler;
  final historyRequests = <http.Request>[];
  final registered = <Map<String, dynamic>>[];

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    if (request.method == 'POST' && path.endsWith('/sanitary-events')) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      registered.add({
        'id': 'new${registered.length}',
        'type': body['type'],
        'status': 'COMPLETED',
        'occurredAt': body['occurredAt'],
        'scheduledDate': null,
        'description': body['description'],
      });
      return http.Response('{}', 201);
    }
    if (path.endsWith('/clinical-history')) {
      historyRequests.add(request);
      if (historyHandler != null) return historyHandler!(request);
      final json = jsonDecode(history) as Map<String, dynamic>;
      return http.Response(jsonEncode({...json, 'events': [...json['events'] as List, ...registered]}), 200);
    }
    return http.Response(animalsJson, 200);
  }

  SanitaryRepository repository() =>
      SanitaryRepository(ApiClient(baseUrl: 'https://api.example.com', client: MockClient(handle)));
}

const lola = AnimalOption(id: 'a1', label: 'Lola');

void main() {
  group('repositorio', () {
    test('pide el historial del animal con un GET sin cuerpo', () async {
      final backend = FakeBackend();

      await backend.repository().getClinicalHistory('a1');

      final request = backend.historyRequests.single;
      expect(request.method, 'GET');
      expect(request.url.toString(), 'https://api.example.com/api/v1/animals/a1/clinical-history');
      expect(request.body, isEmpty);
    });

    test('decodifica tipos, estados y fechas conservando el orden del backend', () async {
      final result = await FakeBackend().repository().getClinicalHistory('a1');

      final history = (result as Success<ClinicalHistory>).data;
      expect(history.animalId, 'a1');
      expect(history.message, isEmpty);
      expect(history.events.map((e) => e.id), ['e1', 'e2', 'e3', 'e4', 'e5', 'e6']);
      expect(history.events.map((e) => e.type), [
        SanitaryEventType.treatment,
        SanitaryEventType.vaccination,
        SanitaryEventType.checkup,
        SanitaryEventType.disease,
        SanitaryEventType.other, // tipo desconocido: other, no se oculta
        SanitaryEventType.other,
      ]);
      expect(history.events.map((e) => e.status), [
        SanitaryEventStatus.completed,
        SanitaryEventStatus.completed,
        SanitaryEventStatus.cancelled,
        SanitaryEventStatus.scheduled,
        null, // estado desconocido: null
        SanitaryEventStatus.completed,
      ]);
      expect(history.events.first.occurredAt, DateTime(2026, 10, 5, 8, 30));
      expect(history.events[3].scheduledDate, DateTime(2026, 12, 18));
    });

    test('la fecha visible depende del estado y no se inventa cuando falta', () async {
      final events = ((await FakeBackend().repository().getClinicalHistory('a1')) as Success<ClinicalHistory>).data.events;

      expect(events[0].displayDate, DateTime(2026, 10, 5, 8, 30)); // realizado: occurredAt
      expect(events[1].displayDate, DateTime(2026, 11, 20)); // realizado que estuvo programado: occurredAt, no scheduledDate
      expect(events[2].displayDate, DateTime(2026, 11, 25)); // cancelado: scheduledDate
      expect(events[3].displayDate, DateTime(2026, 12, 18)); // programado: scheduledDate
      expect(events[4].displayDate, isNull); // sin estado
      expect(events[5].displayDate, isNull); // realizado sin occurredAt: no se usa otra fecha
    });

    test('descripcion vacia o en blanco queda en null', () async {
      final events = ((await FakeBackend().repository().getClinicalHistory('a1')) as Success<ClinicalHistory>).data.events;

      expect(events.map((e) => e.description), ['Antibiotico', null, 'Control cancelado', null, null, null]);
    });

    test('historial vacio: lista vacia y mensaje del backend', () async {
      final result = await FakeBackend(history: emptyJson).repository().getClinicalHistory('a1');

      final history = (result as Success<ClinicalHistory>).data;
      expect(history.events, isEmpty);
      expect(history.message, 'Sin registros.');
    });

    test('un error HTTP devuelve el mensaje del backend', () async {
      final backend = FakeBackend()
        ..historyHandler = (_) async => http.Response('{"message":"Parametro invalido: animalId"}', 400);

      final result = await backend.repository().getClinicalHistory('xyz');

      expect(result, isA<Failure<ClinicalHistory>>()
          .having((f) => f.message, 'message', 'Parametro invalido: animalId')
          .having((f) => f.isConnectionError, 'isConnectionError', false));
    });

    test('sin conexion devuelve un error de conexion', () async {
      final backend = FakeBackend()..historyHandler = (_) async => throw const SocketException('sin red');

      final result = await backend.repository().getClinicalHistory('a1');

      expect(result, isA<Failure<ClinicalHistory>>().having((f) => f.isConnectionError, 'isConnectionError', true));
    });
  });

  group('view model', () {
    test('carga el historial del animal preseleccionado: pasa por cargando y termina con datos', () async {
      final backend = FakeBackend();
      final vm = ClinicalHistoryViewModel(backend.repository(), animal: lola);
      final loadingStates = <bool>[];
      vm.addListener(() => loadingStates.add(vm.loading));

      await vm.load();

      expect(loadingStates, [true, false]);
      expect(vm.history!.events, hasLength(6));
      expect(vm.connectionError, isFalse);
      expect(backend.historyRequests.single.url.path, '/api/v1/animals/a1/clinical-history');
    });

    test('con error queda sin historial y reintentar lo carga', () async {
      final backend = FakeBackend()..historyHandler = (_) async => http.Response('{"message":"Error temporal"}', 500);
      final vm = ClinicalHistoryViewModel(backend.repository(), animal: lola);

      await vm.load();
      expect(vm.history, isNull);
      expect(vm.message, 'Error temporal');
      expect(vm.connectionError, isFalse);

      backend.historyHandler = (_) async => throw const SocketException('sin red');
      await vm.load();
      expect(vm.connectionError, isTrue);

      backend.historyHandler = null;
      await vm.load();
      expect(vm.history!.events, hasLength(6));
      expect(vm.message, isEmpty);
      expect(vm.connectionError, isFalse);
    });

    test('una carga nueva descarta la respuesta de la anterior', () async {
      final slow = Completer<http.Response>();
      final backend = FakeBackend()..historyHandler = (_) => slow.future;
      final vm = ClinicalHistoryViewModel(backend.repository(), animal: lola);

      final first = vm.load();
      backend.historyHandler = null;
      await vm.load();
      slow.complete(http.Response(emptyJson, 200));
      await first;

      expect(vm.history!.events, hasLength(6)); // gana la ultima solicitud, no la que respondio tarde
      expect(vm.loading, isFalse);
    });

    test('sin animal preseleccionado carga la lista, elige uno y reemplaza el historial anterior', () async {
      final backend = FakeBackend();
      final vm = ClinicalHistoryViewModel(backend.repository());

      await vm.load(); // sin animal no hace nada
      expect(backend.historyRequests, isEmpty);

      await vm.loadAnimals();
      expect(vm.animals!.map((a) => a.label), ['Lola', 'TAG-2']);

      await vm.selectAnimal(vm.animals!.first);
      expect(vm.history!.animalId, 'a1');

      final slow = Completer<http.Response>();
      backend.historyHandler = (_) => slow.future;
      final pending = vm.selectAnimal(vm.animals!.last);
      expect(vm.history, isNull); // no se muestra el historial de Lola mientras carga el de TAG-2
      expect(vm.loading, isTrue);
      slow.complete(http.Response(emptyJson, 200));
      await pending;
      expect(backend.historyRequests.last.url.path, '/api/v1/animals/a2/clinical-history');
    });

    test('con el animal preseleccionado no se puede cambiar ni carga la lista de animales', () async {
      final backend = FakeBackend();
      final vm = ClinicalHistoryViewModel(backend.repository(), animal: lola);

      await vm.loadAnimals();
      await vm.selectAnimal(const AnimalOption(id: 'a2', label: 'Otro'));

      expect(vm.animals, isNull);
      expect(vm.animal, lola);
      expect(backend.historyRequests, isEmpty);
    });

    test('si falla la lista de animales deja el error y permite reintentar', () async {
      var fail = true;
      final repository = SanitaryRepository(ApiClient(
          baseUrl: 'https://api.example.com',
          client: MockClient((_) async => fail ? throw const SocketException('x') : http.Response(animalsJson, 200))));
      final vm = ClinicalHistoryViewModel(repository);

      await vm.loadAnimals();
      expect(vm.animals, isNull);
      expect(vm.animalsConnectionError, isTrue);

      fail = false;
      await vm.loadAnimals();
      expect(vm.animals, hasLength(2));
    });
  });

  group('pantalla', () {
    Widget host(FakeBackend backend, {AnimalOption? animal, Locale locale = const Locale('es')}) => MaterialApp(
          locale: locale,
          localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(clinicalHistoryRoute(backend.repository(), animal: animal)),
                child: const Text('abrir'),
              ),
            ),
          ),
        );

    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('muestra cada evento con su tipo, estado, fecha en el idioma activo y descripcion', (tester) async {
      await tester.pumpWidget(host(FakeBackend(), animal: lola));
      await open(tester);

      expect(find.text('Historial clínico'), findsOneWidget);
      expect(find.text('Lola'), findsOneWidget);
      expect(find.text('Tratamiento'), findsOneWidget);
      expect(find.text('Antibiotico'), findsOneWidget);
      expect(find.text('5 oct 2026'), findsOneWidget);
      expect(find.text('Realizado'), findsNWidgets(3));
      expect(find.text('Cancelado'), findsOneWidget);
      expect(find.text('Programado'), findsOneWidget);
      expect(find.text('Control cancelado'), findsOneWidget);
      expect(find.text('18 dic 2026'), findsOneWidget);
      expect(find.text('Sin fecha registrada'), findsNWidgets(2)); // sin estado y realizado sin fecha
    });

    testWidgets('en ingles traduce estados, tipos y fechas', (tester) async {
      await tester.pumpWidget(host(FakeBackend(), animal: lola, locale: const Locale('en')));
      await open(tester);

      expect(find.text('Clinical history'), findsOneWidget);
      expect(find.text('Treatment'), findsOneWidget);
      expect(find.text('Completed'), findsNWidgets(3));
      expect(find.text('Scheduled'), findsOneWidget);
      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.text('Oct 5, 2026'), findsOneWidget);
      expect(find.text('No date recorded'), findsNWidgets(2));
    });

    testWidgets('la lista no se desborda con muchos eventos y se desplaza hasta el ultimo', (tester) async {
      final events = [
        for (var i = 0; i < 30; i++)
          '{"id":"x$i","type":"CHECKUP","status":"COMPLETED","occurredAt":"2026-10-01T00:00:00","scheduledDate":null,'
              '"description":"Observacion larga ${'muy ' * 30}$i"}'
      ];
      await tester.pumpWidget(host(FakeBackend(history: '{"animalId":"a1","events":[${events.join(',')}]}'), animal: lola));
      await open(tester);

      await tester.scrollUntilVisible(find.textContaining('muy 29'), 400);
      expect(find.textContaining('muy 29'), findsOneWidget);
      expect(tester.takeException(), isNull); // sin overflow
    });

    testWidgets('mientras carga muestra el indicador de progreso', (tester) async {
      final slow = Completer<http.Response>();
      final backend = FakeBackend()..historyHandler = (_) => slow.future;
      await tester.pumpWidget(host(backend, animal: lola));
      await tester.tap(find.text('abrir'));
      await tester.pump();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      slow.complete(http.Response(emptyJson, 200));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('historial vacio muestra el texto de la app, no el del backend', (tester) async {
      await tester.pumpWidget(host(FakeBackend(history: emptyJson), animal: lola, locale: const Locale('en')));
      await open(tester);

      expect(find.text('No records.'), findsOneWidget);
      expect(find.text('Sin registros.'), findsNothing);
    });

    testWidgets('con error HTTP o sin conexion muestra el mensaje y reintentar recarga', (tester) async {
      final backend = FakeBackend()..historyHandler = (_) async => http.Response('{"message":"Error temporal"}', 500);
      await tester.pumpWidget(host(backend, animal: lola));
      await open(tester);
      expect(find.text('Error temporal'), findsOneWidget);
      expect(find.text('Historial clínico'), findsOneWidget); // la pantalla sigue abierta

      backend.historyHandler = (_) async => throw const SocketException('sin red');
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('No se pudo conectar con el servidor.'), findsOneWidget);

      backend.historyHandler = null;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('Antibiotico'), findsOneWidget);
      expect(find.text('Reintentar'), findsNothing);
    });

    testWidgets('sin animal: pide elegirlo y al elegirlo muestra su historial', (tester) async {
      final backend = FakeBackend();
      await tester.pumpWidget(host(backend));
      await open(tester);

      expect(find.text('Selecciona un animal para ver su historial.'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(backend.historyRequests, isEmpty);

      await tester.tap(find.byKey(const Key('history-animal')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lola').last);
      await tester.pumpAndSettle();

      expect(backend.historyRequests.single.url.path, '/api/v1/animals/a1/clinical-history');
      expect(find.text('Antibiotico'), findsOneWidget);
    });
  });

  testWidgets('desde Calendario: historial del animal y un evento registrado con US-11 aparece al volver', (tester) async {
    SharedPreferences.setMockInitialValues({'session.token': 't', 'session.role': 'VETERINARIO', 'session.name': 'Ana'});
    final backend = FakeBackend(history: emptyJson);
    final dependencies = await AppDependencies.create(
        client: MockClient((request) => request.url.path.endsWith('upcoming')
            ? Future.value(http.Response('{"events":[],"message":"No pending alerts."}', 200))
            : backend.handle(request)));
    await tester.pumpWidget(GethicsApp(dependencies: dependencies));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.history), findsNothing); // solo en Calendario
    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('history-animal')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lola').last);
    await tester.pumpAndSettle();
    expect(find.text('No records.'), findsOneWidget);

    // US-11 con el animal ya fijado: solo falta el tipo.
    await tester.tap(find.text('Register event'));
    await tester.pumpAndSettle();
    expect(find.text('Register sanitary event'), findsOneWidget);
    await tester.tap(find.byKey(const Key('register-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Checkup').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('register-notes')), 'Control de rutina');
    await tester.ensureVisible(find.byKey(const Key('register-submit')));
    await tester.tap(find.byKey(const Key('register-submit')));
    await tester.pumpAndSettle();

    expect(backend.registered, hasLength(1));
    expect(find.text('Sanitary event registered.'), findsOneWidget);
    expect(backend.historyRequests, hasLength(2)); // se recargo al volver
    expect(find.text('No records.'), findsNothing);
    expect(find.text('Control de rutina'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
  });
}
