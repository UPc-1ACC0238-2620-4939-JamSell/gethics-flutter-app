import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gethics/core/common/result.dart';
import 'package:gethics/core/network/api_client.dart';
import 'package:gethics/features/sanitary/data/sanitary_repository.dart';
import 'package:gethics/features/sanitary/presentation/upcoming_events_page.dart';
import 'package:gethics/features/sanitary/presentation/upcoming_events_view_model.dart';
import 'package:gethics/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'sanitary_repository_test.dart' show animalsJson, upcomingJson;

/// Backend simulado: lista de proximos, animales y reprogramacion (respuesta configurable).
class FakeBackend {
  FakeBackend({this.reschedule});

  Future<http.Response> Function(http.Request)? reschedule;
  final rescheduleRequests = <http.Request>[];
  int upcomingCalls = 0;

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    if (path.endsWith('/reschedule')) {
      rescheduleRequests.add(request);
      return reschedule == null ? http.Response('{}', 200) : reschedule!(request);
    }
    if (path.endsWith('upcoming')) {
      upcomingCalls++;
      return http.Response(upcomingJson, 200);
    }
    return http.Response(animalsJson, 200);
  }

  SanitaryRepository repository() =>
      SanitaryRepository(ApiClient(baseUrl: 'https://api.example.com', client: MockClient(handle)));
}

final today = DateTime(2026, 11, 26);

Future<UpcomingEventsViewModel> loadedViewModel(FakeBackend backend) async {
  final vm = UpcomingEventsViewModel(backend.repository(), now: () => DateTime(2026, 11, 26, 10));
  await vm.load();
  return vm;
}

void main() {
  test('el repositorio envia la nueva fecha y las notas al endpoint de reprogramacion', () async {
    final backend = FakeBackend();

    final result = await backend.repository().rescheduleEvent(
        animalId: 'a1', eventId: 'e1', scheduledDate: DateTime(2026, 12, 5), description: 'Segunda dosis');

    expect(result, isA<Success<void>>());
    final request = backend.rescheduleRequests.single;
    expect(request.url.path, '/api/v1/animals/a1/sanitary-events/e1/reschedule');
    expect(jsonDecode(request.body), {'scheduledDate': '2026-12-05', 'description': 'Segunda dosis'});
  });

  test('reprogramar con exito envia notas sin espacios, devuelve true y recarga la lista', () async {
    final backend = FakeBackend();
    final vm = await loadedViewModel(backend);
    final event = vm.events!.first;

    final ok = await vm.reschedule(event, DateTime(2026, 12, 5), '  Control  ');

    expect(ok, isTrue);
    expect(jsonDecode(backend.rescheduleRequests.single.body), {'scheduledDate': '2026-12-05', 'description': 'Control'});
    expect(backend.upcomingCalls, 2);
    expect(vm.rescheduleError, isNull);
    expect(vm.rescheduling, isFalse);
  });

  test('notas vacias se envian como null para conservar las actuales; hoy es una fecha valida', () async {
    final backend = FakeBackend();
    final vm = await loadedViewModel(backend);

    await vm.reschedule(vm.events!.first, today, '   ');

    expect(jsonDecode(backend.rescheduleRequests.single.body), {'scheduledDate': '2026-11-26', 'description': null});
  });

  test('una fecha anterior a hoy no llama al backend', () async {
    final backend = FakeBackend();
    final vm = await loadedViewModel(backend);

    final ok = await vm.reschedule(vm.events!.first, DateTime(2026, 11, 25), 'x');

    expect(ok, isFalse);
    expect(vm.rescheduleError, isA<PastDateRescheduleError>());
    expect(backend.rescheduleRequests, isEmpty);
  });

  test('error del backend y sin conexion quedan en rescheduleError y no recargan', () async {
    final backend = FakeBackend(
        reschedule: (_) async => http.Response('{"message":"Solo un evento programado (SCHEDULED) puede reprogramarse."}', 409));
    final vm = await loadedViewModel(backend);

    expect(await vm.reschedule(vm.events!.first, DateTime(2026, 12, 1), ''), isFalse);
    expect(vm.rescheduleError, isA<ServerRescheduleError>()
        .having((e) => e.serverMessage, 'serverMessage', 'Solo un evento programado (SCHEDULED) puede reprogramarse.'));
    expect(backend.upcomingCalls, 1);

    backend.reschedule = (_) async => throw const SocketException('sin red');
    expect(await vm.reschedule(vm.events!.first, DateTime(2026, 12, 1), ''), isFalse);
    expect(vm.rescheduleError, isA<ConnectionRescheduleError>());

    vm.clearRescheduleError();
    expect(vm.rescheduleError, isNull);
  });

  Widget app(UpcomingEventsViewModel vm) => MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: ChangeNotifierProvider.value(value: vm, child: const UpcomingEventsPage())),
      );

  testWidgets('el dialogo conserva las notas con error y se cierra al reprogramar con exito', (tester) async {
    final backend = FakeBackend(reschedule: (_) async => http.Response('{"message":"Error temporal"}', 500));
    final vm = await loadedViewModel(backend);
    await tester.pumpWidget(app(vm));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reprogramar').first);
    await tester.pumpAndSettle();
    expect(find.text('Reprogramar evento'), findsOneWidget);
    expect(find.text('Aftosa'), findsWidgets); // notas actuales precargadas

    await tester.enterText(find.byKey(const Key('reschedule-notes')), 'Segunda dosis');
    await tester.tap(find.widgetWithText(FilledButton, 'Reprogramar'));
    await tester.pumpAndSettle();

    expect(find.text('Error temporal'), findsOneWidget);
    expect(find.text('Reprogramar evento'), findsOneWidget);
    expect(find.text('Segunda dosis'), findsOneWidget);

    backend.reschedule = null;
    await tester.tap(find.widgetWithText(FilledButton, 'Reprogramar'));
    await tester.pumpAndSettle();

    expect(find.text('Reprogramar evento'), findsNothing);
    expect(jsonDecode(backend.rescheduleRequests.last.body)['description'], 'Segunda dosis');
  });
}
