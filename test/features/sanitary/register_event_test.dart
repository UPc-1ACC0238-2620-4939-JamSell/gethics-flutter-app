import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gethics/app.dart';
import 'package:gethics/core/common/result.dart';
import 'package:gethics/core/common/uuid.dart';
import 'package:gethics/core/di/app_dependencies.dart';
import 'package:gethics/core/network/api_client.dart';
import 'package:gethics/features/sanitary/data/sanitary_repository.dart';
import 'package:gethics/features/sanitary/domain/animal_option.dart';
import 'package:gethics/features/sanitary/domain/upcoming_event.dart';
import 'package:gethics/features/sanitary/presentation/register_event_page.dart';
import 'package:gethics/features/sanitary/presentation/register_event_view_model.dart';
import 'package:gethics/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sanitary_repository_test.dart' show animalsJson;

/// Backend simulado: lista de animales y registro de eventos (respuesta configurable).
class FakeBackend {
  FakeBackend({this.register});

  Future<http.Response> Function(http.Request)? register;
  final registerRequests = <http.Request>[];

  Future<http.Response> handle(http.Request request) async {
    if (request.method == 'POST' && request.url.path.endsWith('/sanitary-events')) {
      registerRequests.add(request);
      return register == null ? http.Response('{"id":"ev1"}', 201) : register!(request);
    }
    return http.Response(animalsJson, 200);
  }

  SanitaryRepository repository() =>
      SanitaryRepository(ApiClient(baseUrl: 'https://api.example.com', client: MockClient(handle)));
}

const lola = AnimalOption(id: 'a1', label: 'Lola');

/// Hoy fijo (26-nov-2026) y ids de solicitud consecutivos (req-1, req-2...).
RegisterEventViewModel viewModel(FakeBackend backend, {AnimalOption? animal = lola}) {
  var requests = 0;
  return RegisterEventViewModel(
    backend.repository(),
    animal: animal,
    now: () => DateTime(2026, 11, 26, 10),
    newRequestId: () => 'req-${++requests}',
  );
}

void main() {
  group('repositorio', () {
    test('arma la solicitud con el animal en la URL, el tipo, la fecha y el clientRequestId', () async {
      final backend = FakeBackend();

      final result = await backend.repository().registerEvent(
            animalId: 'a1',
            type: SanitaryEventType.vaccination,
            occurredAt: DateTime(2026, 11, 20, 15, 30),
            description: 'Aftosa',
            clientRequestId: 'req-1',
          );

      expect(result, isA<Success<void>>());
      final request = backend.registerRequests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/animals/a1/sanitary-events');
      expect(request.headers['content-type'], contains('application/json'));
      expect(jsonDecode(request.body), {
        'type': 'VACCINATION',
        'occurredAt': '2026-11-20T00:00:00',
        'description': 'Aftosa',
        'clientRequestId': 'req-1',
      });
    });

    test('sin observaciones no envia description', () async {
      final backend = FakeBackend();

      await backend.repository().registerEvent(
          animalId: 'a1', type: SanitaryEventType.other, occurredAt: DateTime(2026, 11, 26), clientRequestId: 'req-1');

      expect(jsonDecode(backend.registerRequests.single.body), {
        'type': 'OTHER',
        'occurredAt': '2026-11-26T00:00:00',
        'clientRequestId': 'req-1',
      });
    });

    test('un 200 (reintento idempotente) cuenta como exito', () async {
      final backend = FakeBackend(register: (_) async => http.Response('{"id":"ev1"}', 200));

      final result = await backend.repository().registerEvent(
          animalId: 'a1', type: SanitaryEventType.checkup, occurredAt: DateTime(2026, 11, 26), clientRequestId: 'r');

      expect(result, isA<Success<void>>());
    });

    test('un error HTTP devuelve el mensaje del backend', () async {
      final backend = FakeBackend(
          register: (_) async => http.Response('{"message":"La fecha del evento no puede ser posterior a hoy."}', 400));

      final result = await backend.repository().registerEvent(
          animalId: 'a1', type: SanitaryEventType.checkup, occurredAt: DateTime(2026, 11, 26), clientRequestId: 'r');

      expect(result, isA<Failure<void>>()
          .having((f) => f.message, 'message', 'La fecha del evento no puede ser posterior a hoy.')
          .having((f) => f.isConnectionError, 'isConnectionError', false));
    });

    test('sin conexion devuelve un error de conexion', () async {
      final backend = FakeBackend(register: (_) async => throw const SocketException('sin red'));

      final result = await backend.repository().registerEvent(
          animalId: 'a1', type: SanitaryEventType.checkup, occurredAt: DateTime(2026, 11, 26), clientRequestId: 'r');

      expect(result, isA<Failure<void>>().having((f) => f.isConnectionError, 'isConnectionError', true));
    });

    test('lista los animales activos con nombre o, si no tiene, arete', () async {
      final result = await FakeBackend().repository().getAnimals();

      final animals = (result as Success<List<AnimalOption>>).data;
      expect(animals.map((a) => (a.id, a.label)), [('a1', 'Lola'), ('a2', 'TAG-2')]);
    });

    test('newUuidV4 genera UUID v4 distintos', () {
      final pattern = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
      final ids = {for (var i = 0; i < 20; i++) newUuidV4()};

      expect(ids, hasLength(20));
      expect(ids.every(pattern.hasMatch), isTrue);
    });
  });

  group('view model', () {
    test('registra con el animal preseleccionado, notas sin espacios y hoy como fecha', () async {
      final backend = FakeBackend();
      final vm = viewModel(backend)..selectType(SanitaryEventType.treatment);

      final ok = await vm.submit('  Antibiotico  ');

      expect(ok, isTrue);
      expect(vm.error, isNull);
      expect(vm.submitting, isFalse);
      expect(backend.registerRequests.single.url.path, '/api/v1/animals/a1/sanitary-events');
      expect(jsonDecode(backend.registerRequests.single.body), {
        'type': 'TREATMENT',
        'occurredAt': '2026-11-26T00:00:00',
        'description': 'Antibiotico',
        'clientRequestId': 'req-1',
      });
    });

    test('sin tipo o sin animal no llama al backend', () async {
      final backend = FakeBackend();

      final withoutType = viewModel(backend);
      expect(await withoutType.submit(''), isFalse);
      expect(withoutType.error, isA<MissingFieldsEventError>());

      final withoutAnimal = viewModel(backend, animal: null)..selectType(SanitaryEventType.checkup);
      expect(await withoutAnimal.submit(''), isFalse);
      expect(withoutAnimal.error, isA<MissingFieldsEventError>());

      expect(backend.registerRequests, isEmpty);
    });

    test('una fecha posterior a hoy no llama al backend; hoy y ayer si', () async {
      final backend = FakeBackend();
      final vm = viewModel(backend)..selectType(SanitaryEventType.checkup);

      vm.selectDate(DateTime(2026, 11, 27));
      expect(await vm.submit(''), isFalse);
      expect(vm.error, isA<FutureDateEventError>());
      expect(backend.registerRequests, isEmpty);

      vm.selectDate(DateTime(2026, 11, 25));
      expect(await vm.submit(''), isTrue);
      expect(jsonDecode(backend.registerRequests.single.body)['occurredAt'], '2026-11-25T00:00:00');
    });

    test('error del backend y sin conexion quedan en error; cambiar un campo lo limpia', () async {
      final backend = FakeBackend(register: (_) async => http.Response('{"message":"Error temporal"}', 500));
      final vm = viewModel(backend)..selectType(SanitaryEventType.checkup);

      expect(await vm.submit(''), isFalse);
      expect(vm.error, isA<ServerEventError>().having((e) => e.serverMessage, 'serverMessage', 'Error temporal'));

      backend.register = (_) async => throw const SocketException('sin red');
      expect(await vm.submit(''), isFalse);
      expect(vm.error, isA<ConnectionEventError>());

      vm.selectType(SanitaryEventType.disease);
      expect(vm.error, isNull);
    });

    test('reintentar los mismos datos reutiliza el clientRequestId; cambiarlos genera otro', () async {
      final backend = FakeBackend(register: (_) async => http.Response('{"message":"Error temporal"}', 500));
      final vm = viewModel(backend)..selectType(SanitaryEventType.checkup);

      await vm.submit('igual');
      await vm.submit('igual');
      await vm.submit('distinto');

      final ids = backend.registerRequests.map((r) => jsonDecode(r.body)['clientRequestId']).toList();
      expect(ids, ['req-1', 'req-1', 'req-2']);
    });

    test('un segundo envio mientras el primero sigue en curso no duplica la solicitud', () async {
      final response = Completer<http.Response>();
      final backend = FakeBackend(register: (_) => response.future);
      final vm = viewModel(backend)..selectType(SanitaryEventType.checkup);

      final first = vm.submit('');
      expect(vm.submitting, isTrue);
      expect(await vm.submit(''), isFalse);

      response.complete(http.Response('{}', 201));
      expect(await first, isTrue);
      expect(backend.registerRequests, hasLength(1));
    });

    test('sin animal preseleccionado carga la lista y permite elegir; con error queda el mensaje', () async {
      final vm = viewModel(FakeBackend(), animal: null);
      await vm.loadAnimals();
      expect(vm.animals!.map((a) => a.label), ['Lola', 'TAG-2']);

      vm.selectAnimal(vm.animals!.last);
      expect(vm.animal!.id, 'a2');

      final failing = RegisterEventViewModel(SanitaryRepository(
          ApiClient(baseUrl: 'https://api.example.com', client: MockClient((_) async => throw const SocketException('x')))));
      await failing.loadAnimals();
      expect(failing.animals, isNull);
      expect(failing.animalsConnectionError, isTrue);
    });

    test('con el animal preseleccionado no se puede cambiar ni carga la lista', () async {
      final vm = viewModel(FakeBackend());

      await vm.loadAnimals();
      vm.selectAnimal(const AnimalOption(id: 'a2', label: 'Otro'));

      expect(vm.animals, isNull);
      expect(vm.animal, lola);
    });
  });

  group('pantalla', () {
    Widget host(FakeBackend backend, {AnimalOption? animal, void Function(bool?)? onResult}) => MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  final saved =
                      await Navigator.of(context).push(registerEventRoute(backend.repository(), animal: animal));
                  onResult?.call(saved);
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        );

    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    Future<void> pickType(WidgetTester tester, String label) async {
      await tester.tap(find.byKey(const Key('register-type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    testWidgets('sin completar marca los campos obligatorios y no llama al backend', (tester) async {
      final backend = FakeBackend();
      await tester.pumpWidget(host(backend));
      await open(tester);

      await tester.ensureVisible(find.byKey(const Key('register-submit')));
      await tester.tap(find.byKey(const Key('register-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Campo obligatorio.'), findsNWidgets(2)); // animal y tipo
      expect(backend.registerRequests, isEmpty);
    });

    testWidgets('elegir animal y tipo, registrar y volver con true', (tester) async {
      final backend = FakeBackend();
      bool? result;
      await tester.pumpWidget(host(backend, onResult: (value) => result = value));
      await open(tester);

      await tester.tap(find.byKey(const Key('register-animal')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('TAG-2').last);
      await tester.pumpAndSettle();
      await pickType(tester, 'Vacuna');
      await tester.enterText(find.byKey(const Key('register-notes')), 'Aftosa');
      await tester.ensureVisible(find.byKey(const Key('register-submit')));
      await tester.tap(find.byKey(const Key('register-submit')));
      await tester.pumpAndSettle();

      final request = backend.registerRequests.single;
      expect(request.url.path, '/api/v1/animals/a2/sanitary-events');
      expect(jsonDecode(request.body)['type'], 'VACCINATION');
      expect(jsonDecode(request.body)['description'], 'Aftosa');
      expect(result, isTrue);
      expect(find.text('Registrar evento sanitario'), findsNothing);
    });

    testWidgets('durante la carga el boton y los campos se deshabilitan y un toque extra no duplica', (tester) async {
      final response = Completer<http.Response>();
      final backend = FakeBackend(register: (_) => response.future);
      await tester.pumpWidget(host(backend, animal: lola));
      await open(tester);
      await pickType(tester, 'Chequeo');

      await tester.ensureVisible(find.byKey(const Key('register-submit')));
      await tester.tap(find.byKey(const Key('register-submit')));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('register-submit'))).onPressed, isNull);
      expect(tester.widget<TextField>(find.byKey(const Key('register-notes'))).enabled, isFalse);
      await tester.tap(find.byKey(const Key('register-submit')), warnIfMissed: false);
      await tester.pump();
      expect(backend.registerRequests, hasLength(1));

      response.complete(http.Response('{}', 201));
      await tester.pumpAndSettle();
      expect(find.text('Registrar evento sanitario'), findsNothing);
    });

    testWidgets('con error del servidor o sin conexion se queda en el formulario con lo ingresado', (tester) async {
      final backend = FakeBackend(register: (_) async => http.Response('{"message":"Error temporal"}', 500));
      await tester.pumpWidget(host(backend, animal: lola));
      await open(tester);
      await pickType(tester, 'Chequeo');
      await tester.enterText(find.byKey(const Key('register-notes')), 'Control de rutina');
      await tester.ensureVisible(find.byKey(const Key('register-submit')));

      await tester.tap(find.byKey(const Key('register-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Error temporal'), findsOneWidget);
      expect(find.text('Control de rutina'), findsOneWidget);

      backend.register = (_) async => throw const SocketException('sin red');
      await tester.tap(find.byKey(const Key('register-submit')));
      await tester.pumpAndSettle();
      expect(find.text('No se pudo conectar con el servidor.'), findsOneWidget);
      expect(find.text('Registrar evento sanitario'), findsOneWidget);
    });
  });

  testWidgets('desde la pestana Calendario: boton, formulario, registro y confirmacion', (tester) async {
    SharedPreferences.setMockInitialValues({'session.token': 't', 'session.role': 'VETERINARIO', 'session.name': 'Ana'});
    final backend = FakeBackend(register: (_) async => http.Response('{"id":"ev1"}', 201));
    final dependencies = await AppDependencies.create(
        client: MockClient((request) => request.url.path.endsWith('upcoming')
            ? Future.value(http.Response('{"events":[],"message":"No pending alerts."}', 200))
            : backend.handle(request)));
    await tester.pumpWidget(GethicsApp(dependencies: dependencies));
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsNothing); // solo en Calendario
    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();
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

    expect(backend.registerRequests.single.url.path, '/api/v1/animals/a1/sanitary-events');
    expect(find.text('Sanitary event registered.'), findsOneWidget);
    expect(find.text('Register sanitary event'), findsNothing);
  });
}
