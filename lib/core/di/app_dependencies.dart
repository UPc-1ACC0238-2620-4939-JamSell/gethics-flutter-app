import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/analytics/data/alert_repository.dart';
import '../../features/iam/data/auth_repository.dart';
import '../../features/livestock/data/livestock_repository.dart';
import '../../features/sanitary/data/pending_sanitary_store.dart';
import '../../features/sanitary/data/sanitary_repository.dart';
import '../../features/sanitary/data/sanitary_sync_service.dart';
import '../network/api_client.dart';
import '../session/session_storage.dart';

/// Dependencias compartidas de la app (equivalente al AppContainer de Android). Cada historia agrega aqui sus
/// repositorios, construidos sobre el mismo [ApiClient].
class AppDependencies {
  AppDependencies({required this.session, required this.api, this.sanitarySync})
      : authRepository = AuthRepository(api, session),
        sanitaryRepository = SanitaryRepository(api, offline: sanitarySync),
        livestockRepository = LivestockRepository(api),
        alertRepository = AlertRepository(api);

  final SessionStorage session;
  final ApiClient api;
  final AuthRepository authRepository;
  final SanitaryRepository sanitaryRepository;
  final LivestockRepository livestockRepository;
  final AlertRepository alertRepository;

  /// US-35: cola offline de registrar/programar eventos; null si la base local no se pudo abrir (sin cola, como antes).
  final SanitarySyncService? sanitarySync;

  /// [store] y [reconnections] solo para pruebas; por defecto la base `gethics.db` y la conectividad del dispositivo.
  static Future<AppDependencies> create({
    http.Client? client,
    PendingSanitaryStore? store,
    Stream<void>? reconnections,
  }) async {
    final session = SessionStorage(await SharedPreferences.getInstance());
    final api = ApiClient(client: client ?? http.Client(), tokenProvider: () => session.token);
    final queue = store ?? await _openStore();
    final sync = queue == null
        ? null
        : SanitarySyncService(
            store: queue,
            api: api,
            session: session,
            // Hay red no significa que el backend responda: solo dispara un intento; los errores siguen el backoff.
            reconnections: reconnections ??
                Connectivity()
                    .onConnectivityChanged
                    .where((results) => results.any((result) => result != ConnectivityResult.none))
                    .map<void>((_) {}),
          );
    sync?.start(); // envia lo que quedo pendiente de una ejecucion anterior
    return AppDependencies(session: session, api: api, sanitarySync: sync);
  }

  static Future<PendingSanitaryStore?> _openStore() async {
    try {
      return await PendingSanitaryStore.open();
    } catch (e) {
      debugPrint('US-35: no se pudo abrir la cola offline: $e');
      return null;
    }
  }
}
