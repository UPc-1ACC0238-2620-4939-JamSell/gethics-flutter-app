import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'core/di/app_dependencies.dart';
import 'core/theme/app_theme.dart';
import 'features/iam/presentation/sign_in_page.dart';
import 'features/iam/presentation/sign_in_view_model.dart';
import 'features/veterinary/presentation/vet_home_page.dart';
import 'l10n/app_localizations.dart';

/// Rutas de la app. Rutas nuevas: agregarlas aqui y en [GethicsApp._routes].
abstract final class Routes {
  static const signIn = '/sign-in';
  static const home = '/home';
}

class GethicsApp extends StatelessWidget {
  const GethicsApp({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return Provider<AppDependencies>.value(
      value: dependencies,
      child: MaterialApp(
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        debugShowCheckedModeBanner: false,
        theme: buildGethicsTheme(),
        // Material, Cupertino y Widgets en el idioma de la app (sin el de Cupertino falla en espanol).
        localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        initialRoute: dependencies.session.isSignedIn ? Routes.home : Routes.signIn,
        routes: _routes,
      ),
    );
  }

  Map<String, WidgetBuilder> get _routes => {
        Routes.signIn: (context) => ChangeNotifierProvider(
              create: (_) => SignInViewModel(dependencies.authRepository),
              child: SignInPage(
                onSignedIn: () {
                  dependencies.sanitarySync?.sync(); // US-35: envia lo que este usuario dejo pendiente
                  Navigator.of(context).pushReplacementNamed(Routes.home);
                },
              ),
            ),
        Routes.home: (context) => VetHomePage(
              userName: dependencies.session.name ?? '',
              onSignOut: () async {
                // US-35: las operaciones pendientes se conservan y no se envian con la sesion de otro usuario.
                dependencies.sanitarySync?.suspend();
                await dependencies.authRepository.signOut();
                if (context.mounted) {
                  Navigator.of(context).pushNamedAndRemoveUntil(Routes.signIn, (_) => false);
                }
              },
            ),
      };
}
