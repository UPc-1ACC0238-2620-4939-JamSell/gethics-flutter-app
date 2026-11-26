import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/iam/data/auth_repository.dart';
import '../../features/sanitary/data/sanitary_repository.dart';
import '../network/api_client.dart';
import '../session/session_storage.dart';

/// Dependencias compartidas de la app (equivalente al AppContainer de Android). Cada historia agrega aqui sus
/// repositorios, construidos sobre el mismo [ApiClient].
class AppDependencies {
  AppDependencies({required this.session, required this.api})
      : authRepository = AuthRepository(api, session),
        sanitaryRepository = SanitaryRepository(api);

  final SessionStorage session;
  final ApiClient api;
  final AuthRepository authRepository;
  final SanitaryRepository sanitaryRepository;

  static Future<AppDependencies> create({http.Client? client}) async {
    final session = SessionStorage(await SharedPreferences.getInstance());
    final api = ApiClient(client: client ?? http.Client(), tokenProvider: () => session.token);
    return AppDependencies(session: session, api: api);
  }
}
