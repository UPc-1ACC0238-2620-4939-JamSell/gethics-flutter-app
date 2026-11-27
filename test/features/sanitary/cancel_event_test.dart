import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gethics/core/common/result.dart';
import 'package:gethics/features/sanitary/domain/clinical_history.dart';
import 'package:gethics/features/sanitary/presentation/sanitary_calendar_page.dart';
import 'package:gethics/features/sanitary/presentation/sanitary_calendar_view_model.dart';
import 'package:gethics/features/sanitary/presentation/upcoming_events_view_model.dart';
import 'package:gethics/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'sanitary_calendar_test.dart' show FakeBackend, today;

Future<http.Response> bytesResponse(String json, int status) async => http.Response.bytes(utf8.encode(json), status);

/// Alertas + calendario con el mismo cableado de la app: cancelar o reprogramar recarga el calendario.
Future<(UpcomingEventsViewModel, SanitaryCalendarViewModel)> loadViewModels(FakeBackend backend) async {
  final repository = backend.repository();
  final calendar = SanitaryCalendarViewModel(repository, now: () => today, debounce: Duration.zero);
  final upcoming = UpcomingEventsViewModel(repository, now: () => today, onEventsChanged: calendar.load);
  await upcoming.load();
  await calendar.load();
  return (upcoming, calendar);
}

void main() {
  group('repositorio', () {
    test('hace un POST sin cuerpo con el animalId y el eventId en la ruta', () async {
      final backend = FakeBackend();

      final result = await backend.repository().cancelEvent(animalId: 'a1', eventId: 'e1');

      expect(result, isA<Success<void>>());
      final request = backend.cancelRequests.single;
      expect(request.method, 'POST');
      expect(request.url.toString(), 'https://api.example.com/api/v1/animals/a1/sanitary-events/e1/cancel');
      expect(request.body, isEmpty);
    });

    test('404, 409 y la falta de conexion devuelven un Failure', () async {
      final backend = FakeBackend();
      final repository = backend.repository();

      backend.cancelHandler = (_) => bytesResponse('{"message":"El evento sanitario no existe para este animal."}', 404);
      expect(await repository.cancelEvent(animalId: 'a1', eventId: 'x'), isA<Failure<void>>()
          .having((f) => f.message, 'message', 'El evento sanitario no existe para este animal.')
          .having((f) => f.isConnectionError, 'isConnectionError', false));

      backend.cancelHandler = (_) => bytesResponse('{"message":"Solo un evento programado (SCHEDULED) puede cancelarse."}', 409);
      expect(await repository.cancelEvent(animalId: 'a1', eventId: 'e1'), isA<Failure<void>>()
          .having((f) => f.message, 'message', 'Solo un evento programado (SCHEDULED) puede cancelarse.'));

      backend.cancelHandler = (_) async => throw const SocketException('sin red');
      expect(await repository.cancelEvent(animalId: 'a1', eventId: 'e1'),
          isA<Failure<void>>().having((f) => f.isConnectionError, 'isConnectionError', true));
    });

    test('un evento cancelado se conserva en el historial clinico como CANCELLED', () async {
      final backend = FakeBackend();
      final repository = backend.repository();

      await repository.cancelEvent(animalId: 'a1', eventId: 'e1');
      final history = ((await repository.getClinicalHistory('a1')) as Success<ClinicalHistory>).data;

      expect(history.events.map((e) => e.id), containsAll(['e1', 'e3'])); // no se borro ninguno
      expect(history.events.firstWhere((e) => e.id == 'e1').status, SanitaryEventStatus.cancelled);
      expect(history.events.firstWhere((e) => e.id == 'e3').status, SanitaryEventStatus.scheduled);
    });
  });

  group('view model', () {
    test('cancelar con exito devuelve true, recarga alertas y calendario y el evento desaparece', () async {
      final backend = FakeBackend();
      final (upcoming, calendar) = await loadViewModels(backend);
      final event = upcoming.events!.firstWhere((e) => e.id == 'e1');
      final upcomingBefore = backend.upcomingCalls;
      final monthsBefore = backend.calendarRequests.length;

      final ok = await upcoming.cancelEvent(event);
      await pumpEventQueue();

      expect(ok, isTrue);
      expect(upcoming.cancelError, isNull);
      expect(upcoming.busy, isFalse);
      expect(backend.cancelRequests.single.url.path, '/api/v1/animals/a1/sanitary-events/e1/cancel');
      expect(backend.upcomingCalls, upcomingBefore + 1);
      expect(backend.calendarRequests.length, monthsBefore + 1);
      expect(upcoming.events!.map((e) => e.id), ['e2']);
      expect(calendar.events!.map((e) => e.id), ['e2']);
    });

    test('con error HTTP o de conexion el evento se conserva y no se recarga nada', () async {
      final backend = FakeBackend();
      final (upcoming, calendar) = await loadViewModels(backend);
      final event = upcoming.events!.firstWhere((e) => e.id == 'e1');
      final upcomingBefore = backend.upcomingCalls;
      final monthsBefore = backend.calendarRequests.length;

      backend.cancelHandler = (_) => bytesResponse('{"message":"Solo un evento programado (SCHEDULED) puede cancelarse."}', 409);
      expect(await upcoming.cancelEvent(event), isFalse);
      expect(upcoming.cancelError, isA<ServerCancelError>()
          .having((e) => e.serverMessage, 'serverMessage', 'Solo un evento programado (SCHEDULED) puede cancelarse.'));

      backend.cancelHandler = (_) async => throw const SocketException('sin red');
      expect(await upcoming.cancelEvent(event), isFalse);
      expect(upcoming.cancelError, isA<ConnectionCancelError>());

      expect(upcoming.events!.map((e) => e.id), contains('e1'));
      expect(calendar.events!.map((e) => e.id), contains('e1'));
      expect(backend.upcomingCalls, upcomingBefore);
      expect(backend.calendarRequests.length, monthsBefore);
      expect(upcoming.busy, isFalse); // se puede volver a intentar

      upcoming.clearCancelError();
      expect(upcoming.cancelError, isNull);
    });

    test('una segunda cancelacion o una reprogramacion mientras hay una en curso se ignoran', () async {
      final slow = Completer<http.Response>();
      final backend = FakeBackend();
      final (upcoming, _) = await loadViewModels(backend);
      final e1 = upcoming.events!.firstWhere((e) => e.id == 'e1');
      final e2 = upcoming.events!.firstWhere((e) => e.id == 'e2');
      backend.cancelHandler = (_) => slow.future;

      final first = upcoming.cancelEvent(e1);
      expect(upcoming.cancelling, isTrue);
      expect(upcoming.busy, isTrue);
      expect(await upcoming.cancelEvent(e1), isFalse);
      expect(await upcoming.cancelEvent(e2), isFalse);
      expect(await upcoming.reschedule(e2, DateTime(2026, 12, 15), ''), isFalse);

      slow.complete(http.Response('{}', 200));
      expect(await first, isTrue);
      expect(backend.cancelRequests, hasLength(1));
      expect(backend.rescheduleRequests, isEmpty);
    });

    test('no se puede cancelar mientras se reprograma', () async {
      final backend = FakeBackend();
      final (upcoming, _) = await loadViewModels(backend);
      final e2 = upcoming.events!.firstWhere((e) => e.id == 'e2');

      final reschedule = upcoming.reschedule(e2, DateTime(2026, 12, 15), '');
      expect(upcoming.rescheduling, isTrue);
      expect(await upcoming.cancelEvent(e2), isFalse);
      await reschedule;
      expect(backend.cancelRequests, isEmpty);
      expect(backend.rescheduleRequests, hasLength(1));
    });
  });

  group('pantalla', () {
    Future<(FakeBackend, UpcomingEventsViewModel, SanitaryCalendarViewModel)> pumpPage(
      WidgetTester tester, {
      Locale locale = const Locale('es'),
      Size size = const Size(800, 3000),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final backend = FakeBackend();
      final (upcoming, calendar) = await loadViewModels(backend);
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
      return (backend, upcoming, calendar);
    }

    final cancelButtons = find.byKey(const Key('cancel-event'));

    Future<void> openDialog(WidgetTester tester) async {
      await tester.tap(cancelButtons.first); // la primera tarjeta es la alerta del evento vencido e1 (Lola, Aftosa)
      await tester.pumpAndSettle();
    }

    testWidgets('las tarjetas de alertas y del mes ofrecen Cancelar evento junto a Reprogramar', (tester) async {
      await pumpPage(tester);

      expect(find.text('Cancelar evento'), findsNWidgets(4)); // e1 y e2, en alertas y en noviembre
      expect(find.text('Reprogramar'), findsNWidgets(4));
    });

    testWidgets('en ingles muestra Cancel event y el dialogo en ingles', (tester) async {
      await pumpPage(tester, locale: const Locale('en'));

      expect(find.text('Cancel event'), findsNWidgets(4));
      await openDialog(tester);
      expect(find.text('Cancel this event?'), findsOneWidget);
      expect(find.text('Keep event'), findsOneWidget);
      expect(find.text('The event will be marked as cancelled and kept in the clinical history.'), findsOneWidget);
    });

    testWidgets('el dialogo pide confirmar, resume el evento y distingue Mantener de Cancelar evento', (tester) async {
      await pumpPage(tester);
      await openDialog(tester);

      expect(find.text('¿Cancelar este evento?'), findsOneWidget);
      expect(find.textContaining('Vacuna · Lola'), findsOneWidget);
      expect(find.byKey(const Key('cancel-keep')), findsOneWidget);
      expect(find.byKey(const Key('cancel-confirm')), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Mantener evento'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Cancelar evento'), findsOneWidget);
    });

    testWidgets('Mantener evento cierra el dialogo sin llamar al backend ni cambiar nada', (tester) async {
      final (backend, upcoming, _) = await pumpPage(tester);
      await openDialog(tester);

      await tester.tap(find.byKey(const Key('cancel-keep')));
      await tester.pumpAndSettle();

      expect(find.text('¿Cancelar este evento?'), findsNothing);
      expect(backend.cancelRequests, isEmpty);
      expect(upcoming.events!.map((e) => e.id), contains('e1'));
      expect(find.text('Aftosa'), findsNWidgets(2));
    });

    testWidgets('confirmar cancela, avisa y el evento sale de las alertas y del calendario', (tester) async {
      final (backend, _, _) = await pumpPage(tester);
      expect(find.text('Aftosa'), findsNWidgets(2));
      final monthsBefore = backend.calendarRequests.length;
      final upcomingBefore = backend.upcomingCalls;

      await openDialog(tester);
      await tester.tap(find.byKey(const Key('cancel-confirm')));
      await tester.pumpAndSettle();

      expect(backend.cancelRequests.single.url.path, '/api/v1/animals/a1/sanitary-events/e1/cancel');
      expect(find.text('¿Cancelar este evento?'), findsNothing);
      expect(find.text('Evento cancelado.'), findsOneWidget);
      expect(find.text('Aftosa'), findsNothing); // ni en alertas ni en el mes
      expect(find.text('Revision'), findsNWidgets(2)); // el otro evento sigue
      expect(backend.upcomingCalls, upcomingBefore + 1);
      expect(backend.calendarRequests.length, monthsBefore + 1);
    });

    testWidgets('con error el dialogo sigue abierto con el mensaje y el evento se conserva; se puede reintentar', (tester) async {
      final (backend, _, _) = await pumpPage(tester);
      backend.cancelHandler = (_) => bytesResponse('{"message":"Solo un evento programado (SCHEDULED) puede cancelarse."}', 409);
      await openDialog(tester);

      await tester.tap(find.byKey(const Key('cancel-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Solo un evento programado (SCHEDULED) puede cancelarse.'), findsOneWidget);
      expect(find.text('¿Cancelar este evento?'), findsOneWidget);

      backend.cancelHandler = (_) async => throw const SocketException('sin red');
      await tester.tap(find.byKey(const Key('cancel-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('No se pudo conectar con el servidor.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('cancel-keep')));
      await tester.pumpAndSettle();
      expect(find.text('Aftosa'), findsNWidgets(2)); // se conserva
      expect(find.text('Evento cancelado.'), findsNothing);

      backend.cancelHandler = null; // el reintento funciona
      await openDialog(tester);
      await tester.tap(find.byKey(const Key('cancel-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Aftosa'), findsNothing);
    });

    testWidgets('durante la cancelacion se deshabilitan las acciones, no se puede cerrar y no se duplica la solicitud',
        (tester) async {
      final slow = Completer<http.Response>();
      final (backend, _, _) = await pumpPage(tester);
      backend.cancelHandler = (_) => slow.future;
      await openDialog(tester);

      await tester.tap(find.byKey(const Key('cancel-confirm')));
      await tester.pump();

      expect(find.descendant(of: find.byKey(const Key('cancel-confirm')), matching: find.byType(CircularProgressIndicator)),
          findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('cancel-confirm'))).onPressed, isNull);
      expect(tester.widget<TextButton>(find.byKey(const Key('cancel-keep'))).onPressed, isNull);
      // Las tarjetas de debajo tambien quedan deshabilitadas (cancelar y reprogramar).
      expect(tester.widgetList<ButtonStyleButton>(cancelButtons).every((b) => b.onPressed == null), isTrue);
      expect(tester.widgetList<ButtonStyleButton>(find.widgetWithText(TextButton, 'Reprogramar')).every((b) => b.onPressed == null), isTrue);

      await tester.tap(find.byKey(const Key('cancel-confirm')), warnIfMissed: false);
      await tester.tapAt(const Offset(2, 2)); // fuera del dialogo: no debe cerrarlo mientras se envia
      await tester.pump();
      expect(find.text('¿Cancelar este evento?'), findsOneWidget);
      expect(backend.cancelRequests, hasLength(1));

      slow.complete(http.Response('{}', 200));
      await tester.pumpAndSettle();
      expect(find.text('¿Cancelar este evento?'), findsNothing);
      expect(find.text('Evento cancelado.'), findsOneWidget);
      expect(backend.cancelRequests, hasLength(1));
    });

    testWidgets('Reprogramar de US-47 sigue funcionando junto a Cancelar evento', (tester) async {
      final (backend, _, _) = await pumpPage(tester);

      await tester.tap(find.text('Reprogramar').first);
      await tester.pumpAndSettle();
      expect(find.text('Reprogramar evento'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Reprogramar'));
      await tester.pumpAndSettle();

      expect(backend.rescheduleRequests, hasLength(1));
      expect(backend.cancelRequests, isEmpty);
      expect(find.text('Reprogramar evento'), findsNothing);
    });

    testWidgets('las dos acciones no desbordan en pantalla angosta con texto grande, en espanol ni en ingles', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      for (final locale in const [Locale('es'), Locale('en')]) {
        await pumpPage(tester, locale: locale, size: const Size(320, 4000));
        expect(find.byKey(const Key('cancel-event')), findsWidgets);
        expect(tester.takeException(), isNull, reason: 'overflow en $locale');
      }
    });
  });
}
