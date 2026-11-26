import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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

UpcomingEventsViewModel viewModel(Future<http.Response> Function(http.Request) handler) => UpcomingEventsViewModel(
    SanitaryRepository(ApiClient(baseUrl: 'https://api.example.com', client: MockClient(handler))));

Future<http.Response> ok(http.Request request) async =>
    http.Response(request.url.path.endsWith('upcoming') ? upcomingJson : animalsJson, 200);

Widget page(UpcomingEventsViewModel vm) => MaterialApp(
      locale: const Locale('es'),
      localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: ChangeNotifierProvider.value(value: vm, child: const UpcomingEventsPage())),
    );

void main() {
  test('el ViewModel carga los eventos y cuenta los que requieren atencion', () async {
    final vm = viewModel(ok);

    await vm.load();

    expect(vm.loading, isFalse);
    expect(vm.events!.map((e) => e.id), ['e1', 'e2', 'e3']);
    expect(vm.needAttention, 2);
  });

  test('sin conexion deja events en null y marca el error de conexion; reintentar recupera la lista', () async {
    var offline = true;
    final vm = viewModel((request) async => offline ? throw const SocketException('sin red') : ok(request));

    await vm.load();
    expect(vm.events, isNull);
    expect(vm.connectionError, isTrue);

    offline = false;
    await vm.load();
    expect(vm.events, hasLength(3));
    expect(vm.connectionError, isFalse);
  });

  testWidgets('muestra el aviso, las etiquetas de urgencia y el animal de cada evento', (tester) async {
    final vm = viewModel(ok);
    await vm.load();

    await tester.pumpWidget(page(vm));
    await tester.pumpAndSettle();

    expect(find.text('2 eventos requieren atención'), findsOneWidget);
    expect(find.text('Vencido'), findsOneWidget);
    expect(find.text('Urgente'), findsOneWidget);
    expect(find.text('Próximo'), findsOneWidget);
    expect(find.text('Lola'), findsOneWidget);
    expect(find.text('TAG-2'), findsOneWidget);
    expect(find.text('Animal sin identificar'), findsOneWidget);
    expect(find.textContaining('Venció hace 2 días'), findsOneWidget);
    expect(find.textContaining('Vence mañana'), findsOneWidget);
  });

  testWidgets('sin eventos muestra el aviso de sin alertas', (tester) async {
    final vm = viewModel((_) async => http.Response('{"events":[],"message":null}', 200));
    await vm.load();

    await tester.pumpWidget(page(vm));
    await tester.pumpAndSettle();

    expect(find.text('No hay alertas pendientes.'), findsOneWidget);
  });

  testWidgets('con error muestra Reintentar', (tester) async {
    final vm = viewModel((_) async => throw const SocketException('sin red'));
    await vm.load();

    await tester.pumpWidget(page(vm));
    await tester.pumpAndSettle();

    expect(find.text('No se pudo conectar con el servidor.'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });
}
