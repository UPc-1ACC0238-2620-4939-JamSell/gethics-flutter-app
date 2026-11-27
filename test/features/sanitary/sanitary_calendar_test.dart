import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gethics/app.dart';
import 'package:gethics/core/common/result.dart';
import 'package:gethics/core/di/app_dependencies.dart';
import 'package:gethics/core/network/api_client.dart';
import 'package:gethics/features/sanitary/data/sanitary_repository.dart';
import 'package:gethics/features/sanitary/domain/upcoming_event.dart';
import 'package:gethics/features/sanitary/presentation/sanitary_calendar_page.dart';
import 'package:gethics/features/sanitary/presentation/sanitary_calendar_view_model.dart';
import 'package:gethics/features/sanitary/presentation/upcoming_events_view_model.dart';
import 'package:gethics/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sanitary_repository_test.dart' show animalsJson;

final today = DateTime(2026, 11, 26, 10);

/// Backend simulado con eventos programados en varios meses. El calendario filtra por year/month, las alertas
/// devuelven lo que vence en 7 dias o ya vencio, y reprogramar cambia la fecha del evento (como el backend real).
class FakeBackend {
  final events = <Map<String, dynamic>>[
    {'id': 'e6', 'animalId': 'a1', 'type': 'CHECKUP', 'scheduledDate': '2026-10-15', 'description': 'Octubre'},
    {'id': 'e1', 'animalId': 'a1', 'type': 'VACCINATION', 'scheduledDate': '2026-11-24', 'description': 'Aftosa'},
    {'id': 'e2', 'animalId': 'a2', 'type': 'CHECKUP', 'scheduledDate': '2026-11-27', 'description': 'Revision'},
    {'id': 'e3', 'animalId': 'a1', 'type': 'TREATMENT', 'scheduledDate': '2026-12-10', 'description': 'Control de peso'},
    {'id': 'e4', 'animalId': 'a2', 'type': 'VACCINATION', 'scheduledDate': '2026-12-10', 'description': 'Segunda dosis'},
    {'id': 'e5', 'animalId': 'a1', 'type': 'OTHER', 'scheduledDate': '2027-01-05', 'description': 'Refuerzo'},
  ];

  /// Si devuelve una respuesta, reemplaza a la normal del calendario.
  Future<http.Response>? Function(http.Request)? calendarHandler;
  final calendarRequests = <http.Request>[];
  int upcomingCalls = 0;
  int animalCalls = 0;
  final rescheduleRequests = <http.Request>[];

  // US-33: cancelar no borra el evento; sale del calendario y de las alertas y queda CANCELLED en el historial.
  final cancelled = <String>{};
  final cancelRequests = <http.Request>[];
  Future<http.Response>? Function(http.Request)? cancelHandler;

  List<String> get requestedMonths => calendarRequests.map((r) => '${r.url.queryParameters['year']}-${r.url.queryParameters['month']}').toList();

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    if (path.endsWith('/cancel')) {
      cancelRequests.add(request);
      final override = cancelHandler?.call(request);
      if (override != null) return override;
      final id = path.split('/').reversed.elementAt(1);
      cancelled.add(id);
      return http.Response('{"id":"$id","status":"CANCELLED"}', 200);
    }
    if (path.endsWith('/clinical-history')) {
      final animalId = path.split('/').reversed.elementAt(1);
      return http.Response(
          jsonEncode({
            'animalId': animalId,
            'events': [
              for (final e in events)
                if (e['animalId'] == animalId)
                  {
                    'id': e['id'],
                    'type': e['type'],
                    'status': cancelled.contains(e['id']) ? 'CANCELLED' : 'SCHEDULED',
                    'occurredAt': null,
                    'scheduledDate': e['scheduledDate'],
                    'description': e['description'],
                  },
            ],
          }),
          200);
    }
    if (path.endsWith('/reschedule')) {
      rescheduleRequests.add(request);
      final id = path.split('/').reversed.elementAt(1);
      events.firstWhere((e) => e['id'] == id)['scheduledDate'] = (jsonDecode(request.body) as Map)['scheduledDate'];
      return http.Response('{}', 200);
    }
    if (path.endsWith('sanitary-calendar')) {
      calendarRequests.add(request);
      final override = calendarHandler?.call(request);
      if (override != null) return override;
      final year = int.parse(request.url.queryParameters['year']!);
      final month = int.parse(request.url.queryParameters['month']!);
      final prefix = '$year-${month.toString().padLeft(2, '0')}';
      final inMonth = [
        for (final e in events)
          if ((e['scheduledDate'] as String).startsWith(prefix) && !cancelled.contains(e['id'])) {...e, 'status': 'SCHEDULED'},
      ]..sort((a, b) => (a['scheduledDate'] as String).compareTo(b['scheduledDate'] as String));
      return http.Response(
          jsonEncode({
            'year': year,
            'month': month,
            'events': inMonth,
            'message': inMonth.isEmpty ? 'No hay actividades pendientes.' : null,
          }),
          200);
    }
    if (path.endsWith('upcoming')) {
      upcomingCalls++;
      final limit = DateTime(2026, 12, 3);
      final due = [
        for (final e in events)
          if (!DateTime.parse(e['scheduledDate'] as String).isAfter(limit) && !cancelled.contains(e['id']))
            {
              ...e,
              'daysUntil': DateTime.parse(e['scheduledDate'] as String).difference(DateTime(2026, 11, 26)).inDays,
              'overdue': DateTime.parse(e['scheduledDate'] as String).isBefore(DateTime(2026, 11, 26)),
            },
      ]..removeWhere((e) => e['overdue'] == true && e['id'] == 'e6'); // octubre ya no se avisa en este escenario
      return http.Response(jsonEncode({'events': due, 'message': due.isEmpty ? 'No hay alertas pendientes.' : null}), 200);
    }
    animalCalls++;
    return http.Response(animalsJson, 200);
  }

  SanitaryRepository repository() =>
      SanitaryRepository(ApiClient(baseUrl: 'https://api.example.com', client: MockClient(handle)));
}

SanitaryCalendarViewModel calendarVm(FakeBackend backend, {DateTime? now, Duration debounce = Duration.zero}) =>
    SanitaryCalendarViewModel(backend.repository(), now: () => now ?? today, debounce: debounce);

void main() {
  group('repositorio', () {
    test('pide el mes con year y month', () async {
      final backend = FakeBackend();

      await backend.repository().getCalendar(year: 2026, month: 12, today: today);

      final request = backend.calendarRequests.single;
      expect(request.method, 'GET');
      expect(request.url.toString(), 'https://api.example.com/api/v1/sanitary-calendar?year=2026&month=12');
    });

    test('decodifica animal, tipo, fecha y descripcion; calcula dias y urgencia desde hoy', () async {
      final backend = FakeBackend();
      backend.events.add({'id': 'e7', 'animalId': 'a9', 'type': 'NUEVO', 'scheduledDate': '2026-11-30', 'description': '  '});

      final result = await backend.repository().getCalendar(
          year: 2026, month: 11, today: today, names: const {'a1': 'Lola', 'a2': 'TAG-2'});

      final events = (result as Success<List<UpcomingEvent>>).data;
      expect(events.map((e) => e.id), ['e1', 'e2', 'e7']); // orden del backend
      expect(events.map((e) => e.animalLabel), ['Lola', 'TAG-2', null]);
      expect(events.map((e) => e.type), [SanitaryEventType.vaccination, SanitaryEventType.checkup, SanitaryEventType.other]);
      expect(events.map((e) => e.scheduledDate), [DateTime(2026, 11, 24), DateTime(2026, 11, 27), DateTime(2026, 11, 30)]);
      expect(events.map((e) => e.description), ['Aftosa', 'Revision', null]);
      expect(events.map((e) => e.daysUntil), [-2, 1, 4]);
      expect(events.map((e) => e.urgency), [EventUrgency.overdue, EventUrgency.urgent, EventUrgency.upcoming]);
    });

    test('los dias hasta el evento cuentan dias de calendario aunque haya cambio de horario o de anio', () async {
      final backend = FakeBackend();

      final result = await backend.repository().getCalendar(year: 2027, month: 1, today: DateTime(2026, 12, 31, 23, 59));

      expect((result as Success<List<UpcomingEvent>>).data.single.daysUntil, 5);
    });

    test('ignora lo que no este programado (SCHEDULED)', () async {
      final backend = FakeBackend()
        ..calendarHandler = (_) async => http.Response(
            '{"year":2026,"month":11,"message":null,"events":['
            '{"id":"x1","animalId":"a1","type":"VACCINATION","scheduledDate":"2026-11-28","description":null,"status":"COMPLETED"},'
            '{"id":"x2","animalId":"a1","type":"VACCINATION","scheduledDate":"2026-11-29","description":null,"status":"SCHEDULED"}]}',
            200);

      final result = await backend.repository().getCalendar(year: 2026, month: 11, today: today);

      expect((result as Success<List<UpcomingEvent>>).data.map((e) => e.id), ['x2']);
    });

    test('mes sin eventos devuelve una lista vacia', () async {
      final result = await FakeBackend().repository().getCalendar(year: 2027, month: 6, today: today);

      expect((result as Success<List<UpcomingEvent>>).data, isEmpty);
    });

    test('un error HTTP devuelve el mensaje del backend', () async {
      final backend = FakeBackend()
        ..calendarHandler =
            (_) async => http.Response.bytes(utf8.encode('{"message":"Periodo de calendario inválido."}'), 400); // el backend responde en UTF-8

      final result = await backend.repository().getCalendar(year: 2026, month: 13, today: today);

      expect(result, isA<Failure<List<UpcomingEvent>>>()
          .having((f) => f.message, 'message', 'Periodo de calendario inválido.')
          .having((f) => f.isConnectionError, 'isConnectionError', false));
    });

    test('sin conexion devuelve un error de conexion', () async {
      final backend = FakeBackend()..calendarHandler = (_) async => throw const SocketException('sin red');

      final result = await backend.repository().getCalendar(year: 2026, month: 11, today: today);

      expect(result, isA<Failure<List<UpcomingEvent>>>().having((f) => f.isConnectionError, 'isConnectionError', true));
    });
  });

  group('view model', () {
    test('empieza en el mes actual, carga sus eventos con el nombre del animal y pasa por cargando', () async {
      final backend = FakeBackend();
      final vm = calendarVm(backend);
      final loadingStates = <bool>[];
      vm.addListener(() => loadingStates.add(vm.loading));

      expect(vm.month, DateTime(2026, 11));
      await vm.load();

      expect(backend.requestedMonths, ['2026-11']);
      expect(vm.events!.map((e) => e.animalLabel), ['Lola', 'TAG-2']);
      expect(loadingStates, [true, false]);
    });

    test('navega al mes siguiente y al anterior', () async {
      final backend = FakeBackend();
      final vm = calendarVm(backend);
      await vm.load();

      await vm.nextMonth();
      expect(vm.month, DateTime(2026, 12));
      expect(vm.events!.map((e) => e.id), ['e3', 'e4']);

      await vm.previousMonth();
      await vm.previousMonth();
      expect(vm.month, DateTime(2026, 10));
      expect(vm.events!.map((e) => e.id), ['e6']);
      expect(backend.requestedMonths, ['2026-11', '2026-12', '2026-11', '2026-10']);
    });

    test('diciembre -> enero cambia de anio y enero -> diciembre lo revierte', () async {
      final backend = FakeBackend();
      final vm = calendarVm(backend, now: DateTime(2026, 12, 15));

      await vm.nextMonth();
      expect(vm.month, DateTime(2027, 1));
      expect(backend.requestedMonths.last, '2027-1');
      expect(vm.events!.map((e) => e.id), ['e5']);

      await vm.previousMonth();
      expect(vm.month, DateTime(2026, 12));
      expect(backend.requestedMonths.last, '2026-12');

      final january = calendarVm(backend, now: DateTime(2027, 1, 3));
      await january.previousMonth();
      expect(january.month, DateTime(2026, 12));
    });

    test('al cambiar de mes no muestra los eventos del anterior mientras carga', () async {
      final slow = Completer<http.Response>();
      final backend = FakeBackend();
      final vm = calendarVm(backend);
      await vm.load();

      backend.calendarHandler = (_) => slow.future;
      final pending = vm.nextMonth();
      await pumpEventQueue();

      expect(vm.events, isNull);
      expect(vm.loading, isTrue);

      slow.complete(http.Response('{"events":[]}', 200));
      await pending;
      expect(vm.events, isEmpty);
    });

    test('descarta la respuesta tardia de un mes anterior', () async {
      final slowDecember = Completer<http.Response>();
      final backend = FakeBackend()
        ..calendarHandler = (request) => request.url.queryParameters['month'] == '12' ? slowDecember.future : null;
      final vm = calendarVm(backend);

      final december = vm.nextMonth();
      await pumpEventQueue(); // la solicitud de diciembre ya salio y sigue pendiente
      await vm.nextMonth(); // el usuario pasa a enero
      slowDecember.complete(http.Response(
          '{"events":[{"id":"x","animalId":"a1","type":"CHECKUP","scheduledDate":"2026-12-20","status":"SCHEDULED"}]}', 200));
      await december;

      expect(vm.month, DateTime(2027, 1));
      expect(vm.events!.map((e) => e.id), ['e5']); // no 'x', que es de diciembre
      expect(vm.loading, isFalse);
    });

    test('tocar varias veces seguidas solo consulta el ultimo mes', () async {
      final backend = FakeBackend();
      final vm = calendarVm(backend, debounce: const Duration(milliseconds: 30));

      await Future.wait([vm.nextMonth(), vm.nextMonth(), vm.nextMonth()]);

      expect(vm.month, DateTime(2027, 2));
      expect(backend.requestedMonths, ['2027-2']);
    });

    test('error HTTP y de conexion dejan el mensaje; cambiar de mes y reintentar siguen funcionando', () async {
      final backend = FakeBackend()..calendarHandler = (_) async => http.Response('{"message":"Error temporal"}', 500);
      final vm = calendarVm(backend);

      await vm.load();
      expect(vm.events, isNull);
      expect(vm.message, 'Error temporal');
      expect(vm.connectionError, isFalse);
      expect(vm.loading, isFalse);

      backend.calendarHandler = (_) async => throw const SocketException('sin red');
      await vm.load();
      expect(vm.connectionError, isTrue);

      backend.calendarHandler = null;
      await vm.nextMonth(); // la navegacion no queda bloqueada por el error
      expect(vm.events!.map((e) => e.id), ['e3', 'e4']);
      expect(vm.connectionError, isFalse);
      expect(vm.message, isEmpty);
    });

    test('los nombres de animales se piden una vez al navegar y de nuevo al recargar', () async {
      final backend = FakeBackend();
      final vm = calendarVm(backend);

      await vm.load();
      await vm.nextMonth();
      await vm.nextMonth();
      expect(backend.animalCalls, 1);

      await vm.load();
      expect(backend.animalCalls, 2);
    });

    test('recargar con datos en pantalla los conserva hasta que llega la respuesta', () async {
      final slow = Completer<http.Response>();
      final backend = FakeBackend();
      final vm = calendarVm(backend);
      await vm.load();

      backend.calendarHandler = (_) => slow.future;
      final reload = vm.load();
      await pumpEventQueue();
      expect(vm.events, hasLength(2));
      expect(vm.loading, isTrue);

      slow.complete(http.Response('{"events":[]}', 200));
      await reload;
      expect(vm.events, isEmpty);
    });
  });

  group('pantalla', () {
    // Las alertas (US-46/47) y el calendario (US-12) comparten pantalla; reprogramar recarga el calendario.
    Future<(FakeBackend, SanitaryCalendarViewModel, UpcomingEventsViewModel)> pumpPage(
      WidgetTester tester, {
      Locale locale = const Locale('es'),
      FakeBackend? backend,
      bool tall = true,
    }) async {
      backend ??= FakeBackend();
      if (tall) {
        // La lista construye solo lo visible: con la pantalla alta se ve todo y las pruebas no dependen del scroll.
        tester.view.physicalSize = const Size(800, 3000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
      }
      final repository = backend.repository();
      final calendar = SanitaryCalendarViewModel(repository, now: () => today, debounce: Duration.zero);
      final upcoming = UpcomingEventsViewModel(repository, now: () => today, onEventsChanged: calendar.load);
      await upcoming.load();
      await calendar.load();
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: upcoming),
              ChangeNotifierProvider.value(value: calendar),
            ],
            child: const SanitaryCalendarPage(),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return (backend, calendar, upcoming);
    }

    Future<void> tapNext(WidgetTester tester, [int times = 1]) async {
      for (var i = 0; i < times; i++) {
        await tester.tap(find.byKey(const Key('calendar-next')));
        await tester.pumpAndSettle();
      }
    }

    testWidgets('muestra las alertas y el mes actual con el animal, tipo, fecha y observaciones', (tester) async {
      await pumpPage(tester);

      expect(find.text('Próximos eventos'), findsOneWidget);
      expect(find.text('Noviembre de 2026'), findsOneWidget);
      expect(find.text('2 eventos requieren atención'), findsOneWidget); // US-46 intacto
      expect(find.text('Vencido'), findsNWidgets(2)); // e1 en las alertas y en el mes
      expect(find.text('Aftosa'), findsNWidgets(2));
      expect(find.text('Revision'), findsNWidgets(2));
      expect(find.text('Lola'), findsNWidgets(2));
      expect(find.text('Vacuna'), findsNWidgets(2));
      expect(find.text('Vie, 27 nov'), findsOneWidget); // agrupado por fecha
      expect(find.text('Control de peso'), findsNothing); // es de diciembre
    });

    testWidgets('navega entre meses y las alertas se conservan; diciembre -> enero cambia de anio', (tester) async {
      final (backend, _, _) = await pumpPage(tester);

      await tapNext(tester);
      expect(find.text('Diciembre de 2026'), findsOneWidget);
      expect(find.text('Control de peso'), findsOneWidget);
      expect(find.text('Segunda dosis'), findsOneWidget);
      expect(find.text('Aftosa'), findsOneWidget); // solo en alertas: el mes de noviembre ya no se muestra
      expect(find.text('Vencido'), findsOneWidget);
      expect(find.text('Próximos eventos'), findsOneWidget);
      expect(find.text('Jue, 10 dic'), findsOneWidget); // dos eventos del mismo dia bajo un solo encabezado

      await tapNext(tester);
      expect(find.text('Enero de 2027'), findsOneWidget);
      expect(find.text('Refuerzo'), findsOneWidget);
      expect(backend.requestedMonths, ['2026-11', '2026-12', '2027-1']);

      await tester.tap(find.byKey(const Key('calendar-previous')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('calendar-previous')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('calendar-previous')));
      await tester.pumpAndSettle();
      expect(find.text('Octubre de 2026'), findsOneWidget);
      expect(find.text('Octubre'), findsOneWidget);
    });

    testWidgets('en ingles traduce el mes, los dias y los controles', (tester) async {
      await pumpPage(tester, locale: const Locale('en'));

      expect(find.text('November 2026'), findsOneWidget);
      expect(find.byTooltip('Previous month'), findsOneWidget);
      expect(find.byTooltip('Next month'), findsOneWidget);
      expect(find.text('Fri, Nov 27'), findsOneWidget);

      await tapNext(tester);
      expect(find.text('December 2026'), findsOneWidget);
      expect(find.text('Thu, Dec 10'), findsOneWidget);
    });

    testWidgets('en una pantalla normal el selector de mes se alcanza desplazando bajo las alertas', (tester) async {
      await pumpPage(tester, tall: false);

      await tester.scrollUntilVisible(find.byKey(const Key('calendar-next')), 300);
      await tester.tap(find.byKey(const Key('calendar-next')));
      await tester.pumpAndSettle();

      expect(find.text('Diciembre de 2026'), findsOneWidget);
      expect(tester.takeException(), isNull); // sin desbordamientos
    });

    testWidgets('los botones de mes tienen area tactil de al menos 48 dp', (tester) async {
      await pumpPage(tester);

      for (final key in ['calendar-previous', 'calendar-next']) {
        final size = tester.getSize(find.byKey(Key(key)));
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
    });

    testWidgets('mes sin eventos muestra el aviso y deja seguir navegando', (tester) async {
      await pumpPage(tester);

      await tapNext(tester, 3); // febrero 2027
      expect(find.text('Febrero de 2027'), findsOneWidget);
      expect(find.text('No hay actividades pendientes este mes.'), findsOneWidget);

      await tapNext(tester);
      expect(find.text('Marzo de 2027'), findsOneWidget);
    });

    testWidgets('con error muestra el mensaje, las alertas siguen visibles y reintentar recarga el mes', (tester) async {
      final backend = FakeBackend();
      await pumpPage(tester, backend: backend);

      backend.calendarHandler = (_) async => http.Response('{"message":"Error temporal"}', 500);
      await tapNext(tester);
      expect(find.text('Error temporal'), findsOneWidget);
      expect(find.text('Aftosa'), findsOneWidget); // alertas de US-46 intactas
      expect(find.text('Diciembre de 2026'), findsOneWidget);

      backend.calendarHandler = (_) async => throw const SocketException('sin red');
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('No se pudo conectar con el servidor.'), findsOneWidget);

      backend.calendarHandler = null;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('Control de peso'), findsOneWidget);
      expect(find.text('Reintentar'), findsNothing);
    });

    testWidgets('mientras carga el mes muestra el indicador de progreso', (tester) async {
      final slow = Completer<http.Response>();
      final backend = FakeBackend();
      await pumpPage(tester, backend: backend);

      backend.calendarHandler = (_) => slow.future;
      await tester.tap(find.byKey(const Key('calendar-next')));
      await tester.pump();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Diciembre de 2026'), findsOneWidget);

      slow.complete(http.Response('{"events":[]}', 200));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('si se cambia rapido de mes gana el ultimo y la respuesta tardia no se muestra', (tester) async {
      final slowDecember = Completer<http.Response>();
      final backend = FakeBackend()
        ..calendarHandler = (request) => request.url.queryParameters['month'] == '12' ? slowDecember.future : null;
      await pumpPage(tester, backend: backend);

      await tester.tap(find.byKey(const Key('calendar-next')));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const Key('calendar-next')));
      await tester.pumpAndSettle();
      expect(find.text('Enero de 2027'), findsOneWidget);
      expect(find.text('Refuerzo'), findsOneWidget);

      slowDecember.complete(http.Response(
          '{"events":[{"id":"x","animalId":"a1","type":"CHECKUP","scheduledDate":"2026-12-20","description":"Tardio","status":"SCHEDULED"}]}',
          200));
      await tester.pumpAndSettle();
      expect(find.text('Tardio'), findsNothing);
      expect(find.text('Enero de 2027'), findsOneWidget);
      expect(find.text('Refuerzo'), findsOneWidget);
    });

    testWidgets('tirar para actualizar recarga las alertas y el mes', (tester) async {
      final (backend, _, _) = await pumpPage(tester, tall: false); // el gesto depende de la altura de la pantalla
      final upcomingBefore = backend.upcomingCalls;
      final monthsBefore = backend.calendarRequests.length;

      await tester.drag(find.byType(ListView), const Offset(0, 400));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(backend.upcomingCalls, upcomingBefore + 1);
      expect(backend.calendarRequests.length, monthsBefore + 1);
    });

    testWidgets('reprogramar desde la pantalla conserva el dialogo de US-47 y recarga alertas y mes', (tester) async {
      final (backend, _, _) = await pumpPage(tester);
      final monthsBefore = backend.calendarRequests.length;

      await tester.tap(find.text('Reprogramar').first);
      await tester.pumpAndSettle();
      expect(find.text('Reprogramar evento'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Reprogramar'));
      await tester.pumpAndSettle();

      expect(backend.rescheduleRequests, hasLength(1));
      expect(find.text('Reprogramar evento'), findsNothing);
      expect(backend.calendarRequests.length, monthsBefore + 1);
    });

    testWidgets('un evento reprogramado a otro mes sale del original y aparece en el nuevo', (tester) async {
      final (backend, _, upcoming) = await pumpPage(tester);
      expect(find.text('Revision'), findsNWidgets(2)); // alertas + noviembre

      final event = upcoming.events!.firstWhere((e) => e.id == 'e2');
      await upcoming.reschedule(event, DateTime(2026, 12, 15), '');
      await tester.pumpAndSettle();

      expect(backend.rescheduleRequests, hasLength(1));
      expect(find.text('Noviembre de 2026'), findsOneWidget);
      expect(find.text('Revision'), findsNothing); // ya no esta en noviembre (ni en las alertas: vence el 15 dic)
      expect(find.text('Aftosa'), findsNWidgets(2));

      await tapNext(tester);
      expect(find.text('Diciembre de 2026'), findsOneWidget);
      expect(find.text('Revision'), findsOneWidget);
      expect(find.text('Mar, 15 dic'), findsOneWidget);
    });
  });

  group('conservacion de US-11 y US-14', () {
    testWidgets('la pestana Calendario mantiene el mes, las alertas, registrar evento e historial clinico', (tester) async {
      SharedPreferences.setMockInitialValues({'session.token': 't', 'session.role': 'VETERINARIO', 'session.name': 'Ana'});
      final dependencies = await AppDependencies.create(
          client: MockClient((request) => Future.value(request.url.path.endsWith('sanitary-calendar')
              ? http.Response('{"year":2026,"month":11,"events":[],"message":"No hay actividades pendientes."}', 200)
              : request.url.path.endsWith('upcoming')
                  ? http.Response('{"events":[],"message":"No pending alerts."}', 200)
                  : http.Response(animalsJson, 200))));
      await tester.pumpWidget(GethicsApp(dependencies: dependencies));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.calendar_month_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Upcoming events'), findsOneWidget);
      expect(find.text(DateFormat.yMMMM('en').format(DateTime.now())), findsOneWidget);
      expect(find.text('No pending activities this month.'), findsOneWidget);
      expect(find.text('Register event'), findsOneWidget);
      expect(find.byIcon(Icons.history), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.descendant(of: find.byType(NavigationBar), matching: find.byType(NavigationDestination)), findsNWidgets(3));
    });
  });
}
