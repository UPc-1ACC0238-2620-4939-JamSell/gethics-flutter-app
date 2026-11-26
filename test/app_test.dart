import 'package:flutter_test/flutter_test.dart';
import 'package:gethics/app.dart';
import 'package:gethics/core/di/app_dependencies.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('sin sesion abre el inicio de sesion y avisa si faltan datos', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final dependencies = await AppDependencies.create(client: MockClient((_) async => http.Response('{}', 200)));

    await tester.pumpWidget(GethicsApp(dependencies: dependencies));
    await tester.pumpAndSettle();

    expect(find.text('Gethics'), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.text('Enter your email and password.'), findsOneWidget);
  });

  testWidgets('con sesion guardada abre el inicio del veterinario', (tester) async {
    SharedPreferences.setMockInitialValues({'session.token': 't', 'session.role': 'VETERINARIO', 'session.name': 'Ana'});
    final dependencies = await AppDependencies.create(client: MockClient((_) async => http.Response('{}', 200)));

    await tester.pumpWidget(GethicsApp(dependencies: dependencies));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    expect(find.text('Hi, Ana'), findsOneWidget);
  });
}
