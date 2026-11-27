import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gethics/core/common/result.dart';
import 'package:gethics/core/network/api_client.dart';
import 'package:gethics/features/analytics/data/alert_repository.dart';
import 'package:gethics/features/analytics/domain/trend_alert.dart';
import 'package:gethics/features/analytics/presentation/trend_alerts_page.dart';
import 'package:gethics/features/analytics/presentation/trend_alerts_view_model.dart';
import 'package:gethics/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

// US-21: consulta de alertas YA almacenadas. Estas pruebas usan un servidor simulado: verifican las solicitudes y la
// pantalla de la app, no la generacion automatica de tendencias ni ninguna entrega push (que son del backend).

// UUID de prueba: solo existe dentro de las pruebas, nunca en la app.
const ownerA = '11111111-1111-4111-8111-111111111111';
const ownerB = '22222222-2222-4222-8222-222222222222';

const alertsJson = '''
{"alerts":[
 {"id":"a1","trendId":"t1","trendType":"SANITARY","riskLevel":"HIGH","message":"Aumento de casos respiratorios en el hato","status":"PENDING","createdAt":"2026-11-02T12:00:00Z"},
 {"id":"a2","trendId":"t2","trendType":"FINANCIAL","riskLevel":"MEDIUM","message":"Egresos por encima del promedio","status":"SENT","createdAt":"2026-11-01T12:00:00Z"},
 {"id":"a3","trendId":"t3","trendType":"COMBINED","riskLevel":"CRITICAL","message":"Mortalidad y costos en alza","status":"READ","createdAt":"2026-10-30T12:00:00Z"},
 {"id":"a4","trendId":"t4","trendType":"SANITARY","riskLevel":"LOW","message":"Tendencia leve","status":"PENDING","createdAt":null},
 {"id":"a5","trendId":null,"trendType":"NUEVO","riskLevel":"XX","message":"","status":"YY","createdAt":"no-es-fecha"}],
 "message":null}''';

const emptyJson = '{"alerts":[],"message":"No hay alertas registradas."}';

Future<http.Response> utf8Response(String json, int status) async => http.Response.bytes(utf8.encode(json), status);

/// Servidor simulado: devuelve [body] (o lo que diga [handler]) y registra las solicitudes.
class FakeBackend {
  String body = alertsJson;
  Future<http.Response> Function(http.Request)? handler;
  final requests = <http.Request>[];

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    return handler != null ? handler!(request) : utf8Response(body, 200);
  }

  AlertRepository repository() => AlertRepository(ApiClient(baseUrl: 'https://api.example.com', client: MockClient(handle)));
}

void main() {
  group('repositorio', () {
    test('hace un GET a /api/v1/alerts con el ownerId recibido', () async {
      final backend = FakeBackend();

      await backend.repository().getAlerts(ownerA);

      final request = backend.requests.single;
      expect(request.method, 'GET');
      expect(request.url.toString(), 'https://api.example.com/api/v1/alerts?ownerId=$ownerA');
      expect(request.body, isEmpty);
    });

    test('decodifica tipos, riesgos, estados, mensaje y fecha conservando el orden del backend', () async {
      final result = await FakeBackend().repository().getAlerts(ownerA);

      final alerts = (result as Success<List<TrendAlert>>).data;
      expect(alerts.map((a) => a.id), ['a1', 'a2', 'a3', 'a4', 'a5']);
      expect(alerts.map((a) => a.type), [TrendType.sanitary, TrendType.financial, TrendType.combined, TrendType.sanitary, null]);
      expect(alerts.map((a) => a.riskLevel), [RiskLevel.high, RiskLevel.medium, RiskLevel.critical, RiskLevel.low, null]);
      expect(alerts.map((a) => a.status), [AlertStatus.pending, AlertStatus.sent, AlertStatus.read, AlertStatus.pending, null]);
      expect(alerts.first.message, 'Aumento de casos respiratorios en el hato');
      expect(alerts.first.trendId, 't1');
      expect(alerts.first.createdAt, DateTime.utc(2026, 11, 2, 12));
    });

    test('campos nulos o valores desconocidos no se inventan ni rompen la lectura', () async {
      final alerts = ((await FakeBackend().repository().getAlerts(ownerA)) as Success<List<TrendAlert>>).data;

      expect(alerts[3].createdAt, isNull); // fecha null
      final unknown = alerts[4];
      expect(unknown.type, isNull);
      expect(unknown.riskLevel, isNull);
      expect(unknown.status, isNull);
      expect(unknown.createdAt, isNull); // fecha ilegible
      expect(unknown.message, isEmpty);
      expect(unknown.trendId, isEmpty);
    });

    test('lista vacia', () async {
      final backend = FakeBackend()..body = emptyJson;

      final result = await backend.repository().getAlerts(ownerA);

      expect((result as Success<List<TrendAlert>>).data, isEmpty);
    });

    test('un error HTTP devuelve el mensaje del backend', () async {
      final backend = FakeBackend()..handler = (_) => utf8Response('{"message":"Parametro invalido: ownerId"}', 400);

      final result = await backend.repository().getAlerts('xyz');

      expect(result, isA<Failure<List<TrendAlert>>>()
          .having((f) => f.message, 'message', 'Parametro invalido: ownerId')
          .having((f) => f.isConnectionError, 'isConnectionError', false));
    });

    test('sin conexion devuelve un error de conexion', () async {
      final backend = FakeBackend()..handler = (_) async => throw const SocketException('sin red');

      final result = await backend.repository().getAlerts(ownerA);

      expect(result, isA<Failure<List<TrendAlert>>>().having((f) => f.isConnectionError, 'isConnectionError', true));
    });
  });

  group('view model', () {
    test('sin propietario valido no consulta nada', () async {
      final backend = FakeBackend();
      for (final owner in [null, '', 'abc', '11111111-1111-1111-1111', 'zzzzzzzz-1111-4111-8111-111111111111']) {
        final vm = TrendAlertsViewModel(backend.repository(), ownerId: owner);

        await vm.load();

        expect(vm.hasOwner, isFalse, reason: 'owner=$owner');
        expect(vm.alerts, isNull);
      }
      expect(backend.requests, isEmpty);
    });

    test('carga las alertas del propietario, pasa por cargando y por defecto solo muestra las sanitarias', () async {
      final backend = FakeBackend();
      final vm = TrendAlertsViewModel(backend.repository(), ownerId: ownerA);
      final loadingStates = <bool>[];
      vm.addListener(() => loadingStates.add(vm.loading));

      await vm.load();

      expect(loadingStates, [true, false]);
      expect(backend.requests.single.url.queryParameters['ownerId'], ownerA);
      // Se ocultan la financiera, la combinada y la de tipo desconocido (podria ser financiera); orden del backend.
      expect(vm.alerts!.map((a) => a.id), ['a1', 'a4']);
    });

    test('con todos los tipos permitidos muestra todas las alertas, tambien la de tipo desconocido, en el orden del backend', () async {
      final vm = TrendAlertsViewModel(FakeBackend().repository(), ownerId: ownerA, allowedTypes: TrendType.values.toSet());

      await vm.load();

      expect(vm.alerts!.map((a) => a.id), ['a1', 'a2', 'a3', 'a4', 'a5']);
    });

    test('lista vacia queda vacia (no es un error)', () async {
      final backend = FakeBackend()..body = emptyJson;
      final vm = TrendAlertsViewModel(backend.repository(), ownerId: ownerA);

      await vm.load();

      expect(vm.alerts, isEmpty);
      expect(vm.connectionError, isFalse);
    });

    test('con error HTTP o de conexion queda el mensaje y reintentar recarga', () async {
      final backend = FakeBackend()..handler = (_) => utf8Response('{"message":"Error temporal"}', 500);
      final vm = TrendAlertsViewModel(backend.repository(), ownerId: ownerA);

      await vm.load();
      expect(vm.alerts, isNull);
      expect(vm.message, 'Error temporal');
      expect(vm.connectionError, isFalse);

      backend.handler = (_) async => throw const SocketException('sin red');
      await vm.load();
      expect(vm.connectionError, isTrue);

      backend.handler = null;
      await vm.load();
      expect(vm.alerts!.map((a) => a.id), ['a1', 'a4']);
      expect(vm.message, isEmpty);
      expect(vm.connectionError, isFalse);
    });

    test('al cambiar de propietario descarta la respuesta tardia del anterior', () async {
      final slowA = Completer<http.Response>();
      final backend = FakeBackend()
        ..handler = (request) => request.url.queryParameters['ownerId'] == ownerA
            ? slowA.future
            : utf8Response('{"alerts":[{"id":"b1","trendId":"t","trendType":"SANITARY","riskLevel":"LOW","message":"De B","status":"SENT","createdAt":null}]}', 200);
      final vm = TrendAlertsViewModel(backend.repository(), ownerId: ownerA);

      final first = vm.load();
      await pumpEventQueue(); // la solicitud de A salio y sigue pendiente
      await vm.selectOwner(ownerB);
      slowA.complete(utf8Response(alertsJson, 200));
      await first;

      expect(vm.ownerId, ownerB);
      expect(vm.alerts!.map((a) => a.id), ['b1']); // no las de A
      expect(vm.loading, isFalse);
    });

    test('cambiar a un propietario no valido limpia las alertas y no consulta; el mismo propietario no recarga', () async {
      final backend = FakeBackend();
      final vm = TrendAlertsViewModel(backend.repository(), ownerId: ownerA);
      await vm.load();
      expect(backend.requests, hasLength(1));

      await vm.selectOwner(ownerA);
      expect(backend.requests, hasLength(1));

      await vm.selectOwner('no-es-uuid');
      expect(vm.hasOwner, isFalse);
      expect(vm.alerts, isNull);
      expect(backend.requests, hasLength(1));
    });
  });

  group('pantalla', () {
    Widget app(Widget home, {Locale locale = const Locale('es')}) => MaterialApp(
          locale: locale,
          localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        );

    Future<void> openRoute(
      WidgetTester tester,
      FakeBackend backend, {
      String? owner = ownerA,
      Locale locale = const Locale('es'),
      Set<TrendType> allowedTypes = const {TrendType.sanitary},
      Size size = const Size(800, 3000),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context)
                .push(trendAlertsRoute(backend.repository(), ownerId: owner, allowedTypes: allowedTypes)),
            child: const Text('abrir'),
          ),
        ),
        locale: locale,
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('la ruta abre la pantalla, consulta al propietario y se puede volver', (tester) async {
      final backend = FakeBackend();
      await openRoute(tester, backend);

      expect(find.text('Alertas por tendencias'), findsOneWidget);
      expect(backend.requests.single.url.queryParameters['ownerId'], ownerA);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Alertas por tendencias'), findsNothing);
      expect(find.text('abrir'), findsOneWidget);
    });

    testWidgets('en espanol muestra tipo, riesgo, mensaje del backend, estado y fecha; oculta lo financiero por defecto', (tester) async {
      await openRoute(tester, FakeBackend());

      expect(find.text('Tendencia sanitaria'), findsNWidgets(2));
      expect(find.text('Riesgo alto'), findsOneWidget);
      expect(find.text('Riesgo bajo'), findsOneWidget);
      expect(find.text('Aumento de casos respiratorios en el hato'), findsOneWidget); // tal como llega
      expect(find.textContaining('Pendiente · 2 nov 2026'), findsOneWidget);
      expect(find.text('Pendiente'), findsOneWidget); // la alerta sin fecha solo muestra el estado
      expect(find.text('Tendencia financiera'), findsNothing);
      expect(find.text('Egresos por encima del promedio'), findsNothing);
    });

    testWidgets('en ingles traduce tipos, riesgos, estados y fechas; con todos los tipos permitidos los muestra y diferencia por icono',
        (tester) async {
      await openRoute(tester, FakeBackend(), locale: const Locale('en'), allowedTypes: TrendType.values.toSet());

      expect(find.text('Trend alerts'), findsOneWidget);
      expect(find.text('Health trend'), findsNWidgets(2));
      expect(find.text('Financial trend'), findsOneWidget);
      expect(find.text('Combined trend'), findsOneWidget);
      expect(find.text('High risk'), findsOneWidget);
      expect(find.text('Medium risk'), findsOneWidget);
      expect(find.text('Critical risk'), findsOneWidget);
      expect(find.text('Low risk'), findsOneWidget);
      expect(find.textContaining('Pending · Nov 2, 2026'), findsOneWidget);
      expect(find.textContaining('Sent · Nov 1, 2026'), findsOneWidget);
      expect(find.textContaining('Read · Oct 30, 2026'), findsOneWidget);
      // El riesgo no depende solo del color: cada nivel tiene su icono (la de tipo desconocido, uno neutro).
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.byIcon(Icons.dangerous_outlined), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(find.byIcon(Icons.notifications_none_outlined), findsOneWidget);
    });

    testWidgets('lista vacia: texto localizado, no el del backend', (tester) async {
      await openRoute(tester, FakeBackend()..body = emptyJson, locale: const Locale('en'));

      expect(find.text('No alerts registered.'), findsOneWidget);
      expect(find.text('No hay alertas registradas.'), findsNothing);
    });

    testWidgets('sin propietario valido muestra el aviso y no hace ninguna consulta', (tester) async {
      final backend = FakeBackend();
      await openRoute(tester, backend, owner: null);

      expect(find.text('No hay un propietario seleccionado para consultar sus alertas.'), findsOneWidget);
      expect(backend.requests, isEmpty);
    });

    testWidgets('mientras carga muestra el indicador de progreso', (tester) async {
      final slow = Completer<http.Response>();
      final backend = FakeBackend()..handler = (_) => slow.future;
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(trendAlertsRoute(backend.repository(), ownerId: ownerA)),
          child: const Text('abrir'),
        ),
      )));
      await tester.tap(find.text('abrir'));
      await tester.pump();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      slow.complete(utf8Response(alertsJson, 200));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('con error HTTP o sin conexion muestra el mensaje y Reintentar recarga', (tester) async {
      final backend = FakeBackend()..handler = (_) => utf8Response('{"message":"Error temporal"}', 500);
      await openRoute(tester, backend);
      expect(find.text('Error temporal'), findsOneWidget);

      backend.handler = (_) async => throw const SocketException('sin red');
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('No se pudo conectar con el servidor.'), findsOneWidget);

      backend.handler = null;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('Aumento de casos respiratorios en el hato'), findsOneWidget);
      expect(find.text('Reintentar'), findsNothing);
    });

    testWidgets('tirar para actualizar vuelve a consultar', (tester) async {
      final backend = FakeBackend();
      await openRoute(tester, backend, size: const Size(800, 600));

      await tester.drag(find.byType(ListView), const Offset(0, 400));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(backend.requests, hasLength(2));
    });

    testWidgets('mensajes largos en pantalla angosta con texto grande no desbordan, en espanol ni en ingles', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      final long = 'Mensaje muy largo ' * 25;
      final backend = FakeBackend()
        ..body = '{"alerts":[{"id":"x","trendId":"t","trendType":"SANITARY","riskLevel":"CRITICAL","message":"$long","status":"PENDING","createdAt":"2026-11-02T12:00:00Z"}]}';
      for (final locale in const [Locale('es'), Locale('en')]) {
        await openRoute(tester, backend, locale: locale, size: const Size(320, 4000));
        expect(find.textContaining('Mensaje muy largo'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'overflow en $locale');
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
      }
    });
  });
}
