import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gethics/core/common/result.dart';
import 'package:gethics/core/network/api_client.dart';
import 'package:gethics/core/session/session_storage.dart';
import 'package:gethics/features/sanitary/data/pending_sanitary_store.dart';
import 'package:gethics/features/sanitary/data/sanitary_sync_service.dart';
import 'package:gethics/features/sanitary/domain/upcoming_event.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// US-35 en un dispositivo Android real o emulador: plugins nativos de sqflite y connectivity_plus. El HTTP es simulado
/// (no escribe en el backend desplegado). Ejecutar con: `flutter test integration_test -d <dispositivo>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('la cola SQLite nativa sobrevive a reabrir la base y se sincroniza con el mismo clientRequestId',
      (tester) async {
    final path = '${await getDatabasesPath()}/us35_integration.db';
    await deleteDatabase(path);
    SharedPreferences.setMockInitialValues({'session.token': 't7', 'session.userId': '7'});
    final session = SessionStorage(await SharedPreferences.getInstance());
    var online = false;
    final sent = <String>[];
    final api = ApiClient(
      baseUrl: 'https://api.example.com',
      tokenProvider: () => session.token,
      client: MockClient((request) async {
        if (!online) throw const SocketException('sin red');
        sent.add(jsonDecode(request.body)['clientRequestId'] as String);
        return http.Response('{"id":"ev1"}', 201);
      }),
    );
    const request = SanitaryRequest(
      operation: SanitaryOperation.register,
      animalId: 'a1',
      type: SanitaryEventType.checkup,
      date: '2026-11-26T00:00:00',
      clientRequestId: '6f1f2c1e-0000-4000-8000-000000000001',
    );

    final store = await PendingSanitaryStore.open(path: path);
    final offlineSync = SanitarySyncService(store: store, api: api, session: session, retryDelay: (_) => const Duration(hours: 1));
    final saved = await offlineSync.save(request);
    expect((saved as Success<SanitarySaveResult>).data, SanitarySaveResult.queued);
    offlineSync.dispose();
    await store.close(); // como si la app se cerrara

    online = true;
    final reopened = await PendingSanitaryStore.open(path: path);
    expect((await reopened.pending('7')).single.clientRequestId, request.clientRequestId);
    final sync = SanitarySyncService(store: reopened, api: api, session: session);
    await sync.sync();
    expect(sent, [request.clientRequestId]);
    expect(await reopened.all('7'), isEmpty);
    sync.dispose();
    await reopened.close();
    await deleteDatabase(path);
  });

  testWidgets('connectivity_plus responde en el dispositivo', (tester) async {
    final results = await Connectivity().checkConnectivity();
    expect(results, isNotEmpty);
  });
}
