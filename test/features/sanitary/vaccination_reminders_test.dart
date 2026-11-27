import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gethics/app.dart';
import 'package:gethics/core/common/result.dart';
import 'package:gethics/core/di/app_dependencies.dart';
import 'package:gethics/features/sanitary/data/sanitary_sync_service.dart';
import 'package:gethics/features/sanitary/domain/animal_option.dart';
import 'package:gethics/features/sanitary/domain/clinical_history.dart';
import 'package:gethics/features/sanitary/domain/upcoming_event.dart' show SanitaryEventType;
import 'package:gethics/features/sanitary/presentation/register_event_page.dart';
import 'package:gethics/features/sanitary/presentation/register_event_view_model.dart';
import 'package:gethics/features/sanitary/presentation/sanitary_calendar_page.dart';
import 'package:gethics/features/sanitary/presentation/sanitary_calendar_view_model.dart';
import 'package:gethics/features/sanitary/presentation/upcoming_events_view_model.dart';
import 'package:gethics/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sanitary_calendar_test.dart' show FakeBackend, today;

// US-13 (parte que el backend permite hoy): programar una vacuna y registrarla como aplicada. Estas pruebas usan un
// servidor simulado: verifican las solicitudes de la app, NO la entrega de notificaciones push (el backend no envia
// ninguna: su adaptador de notificaciones solo escribe en el log).

const lola = AnimalOption(id: 'a1', label: 'Lola');

Future<http.Response> utf8Response(String json, int status) async => http.Response.bytes(utf8.encode(json), status);

RegisterEventViewModel scheduleVm(FakeBackend backend, {AnimalOption? animal = lola}) {
  var requests = 0;
  return RegisterEventViewModel(
    backend.repository(),
    animal: animal,
    scheduleVaccination: true,
    now: () => today,
    newRequestId: () => 'req-${++requests}',
  );
}

void main() {
  group('repositorio', () {
    test('programar una vacuna hace POST /scheduled con tipo VACCINATION, fecha ISO y clientRequestId', () async {
      final backend = FakeBackend();

      final result = await backend.repository().scheduleVaccination(
          animalId: 'a1', scheduledDate: DateTime(2026, 12, 20, 15), description: 'Aftosa', clientRequestId: 'req-1');

      expect(result, isA<Success<void>>());
      final request = backend.scheduleRequests.single;
      expect(request.method, 'POST');
      expect(request.url.toString(), 'https://api.example.com/api/v1/animals/a1/sanitary-events/scheduled');
      expect(jsonDecode(request.body),
          {'type': 'VACCINATION', 'scheduledDate': '2026-12-20', 'description': 'Aftosa', 'clientRequestId': 'req-1'});
    });

    test('sin observaciones no envia description', () async {
      final backend = FakeBackend();

      await backend.repository().scheduleVaccination(animalId: 'a1', scheduledDate: DateTime(2026, 12, 20), clientRequestId: 'r');

      expect(jsonDecode(backend.scheduleRequests.single.body),
          {'type': 'VACCINATION', 'scheduledDate': '2026-12-20', 'clientRequestId': 'r'});
    });

    test('programar: error HTTP con el mensaje del backend y error de conexion', () async {
      final backend = FakeBackend();
      final repository = backend.repository();

      backend.scheduleHandler = (_) => utf8Response('{"message":"La fecha programada no puede ser anterior a hoy."}', 400);
      expect(await repository.scheduleVaccination(animalId: 'a1', scheduledDate: DateTime(2020), clientRequestId: 'r'),
          isA<Failure<void>>().having((f) => f.message, 'message', 'La fecha programada no puede ser anterior a hoy.'));

      backend.scheduleHandler = (_) async => throw const SocketException('sin red');
      expect(await repository.scheduleVaccination(animalId: 'a1', scheduledDate: DateTime(2026, 12), clientRequestId: 'r'),
          isA<Failure<void>>().having((f) => f.isConnectionError, 'isConnectionError', true));
    });

    test('marcar como aplicada hace POST /complete con occurredAt a las 00:00:00 y sin description', () async {
      final backend = FakeBackend();

      final result = await backend.repository().completeEvent(animalId: 'a1', eventId: 'e1', occurredAt: DateTime(2026, 11, 20, 18));

      expect(result, isA<Success<void>>());
      final request = backend.completeRequests.single;
      expect(request.method, 'POST');
      expect(request.url.toString(), 'https://api.example.com/api/v1/animals/a1/sanitary-events/e1/complete');
      expect(jsonDecode(request.body), {'occurredAt': '2026-11-20T00:00:00'});
    });

    test('aplicar: 404, 409 y falta de conexion devuelven Failure', () async {
      final backend = FakeBackend();
      final repository = backend.repository();

      backend.completeHandler = (_) => utf8Response('{"message":"El evento sanitario no existe para este animal."}', 404);
      expect(await repository.completeEvent(animalId: 'a1', eventId: 'x', occurredAt: today),
          isA<Failure<void>>().having((f) => f.message, 'message', 'El evento sanitario no existe para este animal.'));

      backend.completeHandler = (_) => utf8Response('{"message":"Solo un evento programado (SCHEDULED) puede registrarse como aplicado."}', 409);
      expect(await repository.completeEvent(animalId: 'a1', eventId: 'e1', occurredAt: today), isA<Failure<void>>());

      backend.completeHandler = (_) async => throw const SocketException('sin red');
      expect(await repository.completeEvent(animalId: 'a1', eventId: 'e1', occurredAt: today),
          isA<Failure<void>>().having((f) => f.isConnectionError, 'isConnectionError', true));
    });
  });

  group('programar vacuna (view model)', () {
    test('programa para hoy con el animal preseleccionado y el tipo fijo en vacuna', () async {
      final backend = FakeBackend();
      final vm = scheduleVm(backend);

      expect(vm.scheduling, isTrue);
      expect(vm.type, SanitaryEventType.vaccination);
      expect(await vm.submit('  Refuerzo  '), SanitarySaveResult.sent);

      expect(backend.scheduleRequests.single.url.path, '/api/v1/animals/a1/sanitary-events/scheduled');
      expect(jsonDecode(backend.scheduleRequests.single.body),
          {'type': 'VACCINATION', 'scheduledDate': '2026-11-26', 'description': 'Refuerzo', 'clientRequestId': 'req-1'});
    });

    test('acepta fechas futuras y rechaza las anteriores a hoy sin llamar al backend', () async {
      final backend = FakeBackend();
      final vm = scheduleVm(backend);

      vm.selectDate(DateTime(2026, 11, 25));
      expect(await vm.submit(''), isNull);
      expect(vm.error, isA<PastDateEventError>());
      expect(backend.scheduleRequests, isEmpty);

      vm.selectDate(DateTime(2027, 3, 1));
      expect(await vm.submit(''), SanitarySaveResult.sent);
      expect(jsonDecode(backend.scheduleRequests.single.body)['scheduledDate'], '2027-03-01');
    });

    test('sin animal no llama al backend; con error HTTP o de conexion queda el error', () async {
      final backend = FakeBackend();
      final withoutAnimal = scheduleVm(backend, animal: null);
      expect(await withoutAnimal.submit(''), isNull);
      expect(withoutAnimal.error, isA<MissingFieldsEventError>());
      expect(backend.scheduleRequests, isEmpty);

      final vm = scheduleVm(backend);
      backend.scheduleHandler = (_) => utf8Response('{"message":"Error temporal"}', 500);
      expect(await vm.submit(''), isNull);
      expect(vm.error, isA<ServerEventError>().having((e) => e.serverMessage, 'serverMessage', 'Error temporal'));
      backend.scheduleHandler = (_) async => throw const SocketException('sin red');
      expect(await vm.submit(''), isNull);
      expect(vm.error, isA<ConnectionEventError>());
    });

    test('un reintento con los mismos datos reutiliza el clientRequestId (el backend no duplica la vacuna)', () async {
      final backend = FakeBackend()..scheduleHandler = (_) => utf8Response('{"message":"x"}', 500);
      final vm = scheduleVm(backend);

      await vm.submit('igual');
      await vm.submit('igual');
      await vm.submit('distinto');

      expect(backend.scheduleRequests.map((r) => jsonDecode(r.body)['clientRequestId']), ['req-1', 'req-1', 'req-2']);
    });

    test('un segundo envio en curso no duplica la solicitud', () async {
      final slow = Completer<http.Response>();
      final backend = FakeBackend()..scheduleHandler = (_) => slow.future;
      final vm = scheduleVm(backend);

      final first = vm.submit('');
      expect(await vm.submit(''), isNull);
      slow.complete(http.Response('{}', 201));
      expect(await first, SanitarySaveResult.sent);
      expect(backend.scheduleRequests, hasLength(1));
    });
  });

  group('marcar como aplicada (view model)', () {
    Future<(FakeBackend, UpcomingEventsViewModel, SanitaryCalendarViewModel)> load() async {
      final backend = FakeBackend();
      final repository = backend.repository();
      final calendar = SanitaryCalendarViewModel(repository, now: () => today, debounce: Duration.zero);
      final upcoming = UpcomingEventsViewModel(repository, now: () => today, onEventsChanged: calendar.load);
      await upcoming.load();
      await calendar.load();
      return (backend, upcoming, calendar);
    }

    test('con exito el evento sale de las alertas y del calendario y queda COMPLETED en el historial', () async {
      final (backend, upcoming, calendar) = await load();
      final event = upcoming.events!.firstWhere((e) => e.id == 'e1');

      expect(await upcoming.completeEvent(event, DateTime(2026, 11, 26)), isTrue);
      await pumpEventQueue();

      expect(jsonDecode(backend.completeRequests.single.body), {'occurredAt': '2026-11-26T00:00:00'});
      expect(upcoming.events!.map((e) => e.id), ['e2']);
      expect(calendar.events!.map((e) => e.id), ['e2']);
      final history = ((await backend.repository().getClinicalHistory('a1')) as Success<ClinicalHistory>).data;
      expect(history.events.firstWhere((e) => e.id == 'e1').status, SanitaryEventStatus.completed);
    });

    test('una fecha de aplicacion futura no llama al backend', () async {
      final (backend, upcoming, _) = await load();

      expect(await upcoming.completeEvent(upcoming.events!.first, DateTime(2026, 11, 27)), isFalse);

      expect(upcoming.actionError, isA<FutureDateActionError>());
      expect(backend.completeRequests, isEmpty);
    });

    test('con error se conserva el evento y no se recarga; mientras se envia se ignoran otras acciones', () async {
      final (backend, upcoming, calendar) = await load();
      final event = upcoming.events!.firstWhere((e) => e.id == 'e1');
      final upcomingBefore = backend.upcomingCalls;

      backend.completeHandler = (_) => utf8Response('{"message":"Solo un evento programado (SCHEDULED) puede registrarse como aplicado."}', 409);
      expect(await upcoming.completeEvent(event, today), isFalse);
      expect(upcoming.actionError, isA<ServerActionError>());
      expect(upcoming.events!.map((e) => e.id), contains('e1'));
      expect(calendar.events!.map((e) => e.id), contains('e1'));
      expect(backend.upcomingCalls, upcomingBefore);

      final slow = Completer<http.Response>();
      backend.completeHandler = (_) => slow.future;
      final pending = upcoming.completeEvent(event, today);
      expect(upcoming.completing, isTrue);
      expect(upcoming.busy, isTrue);
      expect(await upcoming.completeEvent(event, today), isFalse);
      expect(await upcoming.cancelEvent(event), isFalse);
      expect(await upcoming.reschedule(event, DateTime(2026, 12, 15), ''), isFalse);
      slow.complete(http.Response('{}', 200));
      expect(await pending, isTrue);
      expect(backend.cancelRequests, isEmpty);
      expect(backend.rescheduleRequests, isEmpty);
    });
  });

  group('pantallas', () {
    Future<void> setSurface(WidgetTester tester, [Size size = const Size(800, 3000)]) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    Widget app(Widget home, {Locale locale = const Locale('es')}) => MaterialApp(
          locale: locale,
          localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        );

    testWidgets('el formulario de programar vacuna no pide tipo, usa "Fecha programada" y vuelve con true', (tester) async {
      await setSurface(tester);
      final backend = FakeBackend();
      SanitarySaveResult? result;
      await tester.pumpWidget(app(Builder(
        builder: (context) => TextButton(
          onPressed: () async =>
              result = await Navigator.of(context).push(scheduleVaccinationRoute(backend.repository(), animal: lola)),
          child: const Text('abrir'),
        ),
      )));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.text('Programar vacuna'), findsOneWidget); // titulo
      expect(find.text('Fecha programada'), findsOneWidget);
      expect(find.byKey(const Key('register-type')), findsNothing);

      await tester.enterText(find.byKey(const Key('register-notes')), 'Aftosa');
      await tester.tap(find.byKey(const Key('register-submit')));
      await tester.pumpAndSettle();

      expect(backend.scheduleRequests.single.url.path, '/api/v1/animals/a1/sanitary-events/scheduled');
      expect(result, SanitarySaveResult.sent);
    });

    testWidgets('registrar un evento (US-11) sigue pidiendo el tipo y su fecha', (tester) async {
      await setSurface(tester);
      final backend = FakeBackend();
      await tester.pumpWidget(app(Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(registerEventRoute(backend.repository(), animal: lola)),
          child: const Text('abrir'),
        ),
      )));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('register-type')), findsOneWidget);
      expect(find.text('Fecha del evento'), findsOneWidget);
      expect(find.text('Registrar evento sanitario'), findsOneWidget);
    });

    testWidgets('solo las vacunas ofrecen Marcar como aplicada; el dialogo registra la aplicacion y quita el evento', (tester) async {
      await setSurface(tester);
      final backend = FakeBackend();
      final repository = backend.repository();
      final calendar = SanitaryCalendarViewModel(repository, now: () => today, debounce: Duration.zero);
      final upcoming = UpcomingEventsViewModel(repository, now: DateTime.now, // el dialogo usa el reloj real
           onEventsChanged: calendar.load);
      await upcoming.load();
      await calendar.load();
      await tester.pumpWidget(app(Scaffold(
        body: MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: upcoming),
            ChangeNotifierProvider.value(value: calendar),
          ],
          child: const SanitaryCalendarPage(),
        ),
      )));
      await tester.pumpAndSettle();

      // e1 es vacuna y e2 es chequeo: 2 tarjetas de vacuna (alerta y mes) frente a 4 tarjetas en total.
      expect(find.byKey(const Key('complete-event')), findsNWidgets(2));
      expect(find.text('Marcar como aplicada'), findsNWidgets(2));
      expect(find.text('Cancelar evento'), findsNWidgets(4)); // US-33 intacto
      expect(find.text('Reprogramar'), findsNWidgets(4)); // US-47 intacto

      await tester.tap(find.byKey(const Key('complete-event')).first);
      await tester.pumpAndSettle();
      expect(find.text('Registrar aplicación'), findsOneWidget);
      expect(find.text('Fecha de aplicación'), findsOneWidget);

      await tester.tap(find.byKey(const Key('complete-confirm')));
      await tester.pumpAndSettle();

      expect(backend.completeRequests.single.url.path, '/api/v1/animals/a1/sanitary-events/e1/complete');
      expect(find.text('Registrar aplicación'), findsNothing);
      expect(find.text('Vacuna registrada como aplicada.'), findsOneWidget);
      expect(find.text('Aftosa'), findsNothing);
      expect(find.byKey(const Key('complete-event')), findsNothing);
    });

    testWidgets('si el backend rechaza la aplicacion el dialogo sigue con el mensaje y se puede cerrar sin cambios', (tester) async {
      await setSurface(tester);
      final backend = FakeBackend()
        ..completeHandler = (_) => utf8Response('{"message":"Solo un evento programado (SCHEDULED) puede registrarse como aplicado."}', 409);
      final repository = backend.repository();
      final calendar = SanitaryCalendarViewModel(repository, now: () => today, debounce: Duration.zero);
      final upcoming = UpcomingEventsViewModel(repository, now: DateTime.now, // el dialogo usa el reloj real
           onEventsChanged: calendar.load);
      await upcoming.load();
      await calendar.load();
      await tester.pumpWidget(app(Scaffold(
        body: MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: upcoming),
            ChangeNotifierProvider.value(value: calendar),
          ],
          child: const SanitaryCalendarPage(),
        ),
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('complete-event')).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('complete-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Solo un evento programado (SCHEDULED) puede registrarse como aplicado.'), findsOneWidget);
      expect(find.text('Registrar aplicación'), findsOneWidget);

      await tester.tap(find.byKey(const Key('complete-cancel')));
      await tester.pumpAndSettle();
      expect(find.text('Aftosa'), findsNWidgets(2));
    });

    testWidgets('desde Calendario: el icono Programar vacuna crea la vacuna y recarga calendario y alertas', (tester) async {
      await setSurface(tester);
      SharedPreferences.setMockInitialValues({'session.token': 't', 'session.role': 'VETERINARIO', 'session.name': 'Ana'});
      final backend = FakeBackend();
      final dependencies = await AppDependencies.create(client: MockClient(backend.handle));
      await tester.pumpWidget(GethicsApp(dependencies: dependencies));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('schedule-vaccination')), findsNothing); // solo en Calendario
      await tester.tap(find.byIcon(Icons.calendar_month_outlined));
      await tester.pumpAndSettle();
      final upcomingBefore = backend.upcomingCalls;
      final monthsBefore = backend.calendarRequests.length;

      await tester.tap(find.byKey(const Key('schedule-vaccination')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('register-animal')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lola').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('register-submit')));
      await tester.pumpAndSettle();

      expect(backend.scheduleRequests.single.url.path, '/api/v1/animals/a1/sanitary-events/scheduled');
      expect(find.text('Vaccination scheduled.'), findsOneWidget); // la app de prueba usa ingles
      expect(backend.upcomingCalls, upcomingBefore + 1);
      expect(backend.calendarRequests.length, monthsBefore + 1);
      expect(find.byKey(const Key('register-submit')), findsNothing); // volvio al calendario
    });

    testWidgets('las tres acciones no desbordan en pantalla angosta con texto grande, en espanol ni en ingles', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      for (final locale in const [Locale('es'), Locale('en')]) {
        await setSurface(tester, const Size(320, 4000));
        final backend = FakeBackend();
        final repository = backend.repository();
        final calendar = SanitaryCalendarViewModel(repository, now: () => today, debounce: Duration.zero);
        final upcoming = UpcomingEventsViewModel(repository, now: DateTime.now, // el dialogo usa el reloj real
           onEventsChanged: calendar.load);
        await upcoming.load();
        await calendar.load();
        await tester.pumpWidget(app(
          Scaffold(
            body: MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: upcoming),
                ChangeNotifierProvider.value(value: calendar),
              ],
              child: const SanitaryCalendarPage(),
            ),
          ),
          locale: locale,
        ));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('complete-event')), findsWidgets);
        expect(tester.takeException(), isNull, reason: 'overflow en $locale');
      }
    });
  });
}
