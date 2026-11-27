import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/di/app_dependencies.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/state_views.dart';
import '../../sanitary/presentation/clinical_history_page.dart';
import '../../sanitary/presentation/register_event_page.dart';
import '../../sanitary/presentation/sanitary_calendar_page.dart';
import '../../sanitary/presentation/sanitary_calendar_view_model.dart';
import '../../sanitary/presentation/upcoming_events_view_model.dart';

/// Inicio del flujo veterinario: navegacion inferior con Clientes, Calendario y Perfil. Las pestanas sin historia
/// implementada muestran un aviso; cada historia de usuario reemplaza su pestana por la pantalla real.
class VetHomePage extends StatefulWidget {
  const VetHomePage({super.key, required this.userName, required this.onSignOut});

  final String userName;
  final VoidCallback onSignOut;

  @override
  State<VetHomePage> createState() => _VetHomePageState();
}

class _VetHomePageState extends State<VetHomePage> {
  int _tab = 0;

  // US-46 y US-12: se crean una vez para conservar los datos al cambiar de pestana; cargan al abrir Calendario.
  late final UpcomingEventsViewModel _upcoming;
  late final SanitaryCalendarViewModel _calendar;
  bool _upcomingLoaded = false;

  @override
  void initState() {
    super.initState();
    final repository = context.read<AppDependencies>().sanitaryRepository;
    _calendar = SanitaryCalendarViewModel(repository);
    // Reprogramar mueve el evento de mes: el calendario mensual se recarga junto con las alertas.
    _upcoming = UpcomingEventsViewModel(repository, onEventsChanged: _calendar.load);
  }

  @override
  void dispose() {
    _upcoming.dispose();
    _calendar.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    setState(() => _tab = index);
    if (index == 1 && !_upcomingLoaded) {
      _upcomingLoaded = true;
      _upcoming.load();
      _calendar.load();
    }
  }

  // US-11: formulario de registro; sin detalle de animal todavia, el formulario deja elegir el animal.
  Future<void> _registerEvent() async {
    final saved = await Navigator.of(context).push(registerEventRoute(context.read<AppDependencies>().sanitaryRepository));
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).registerEventSuccess)));
    }
  }

  // US-14: historial clinico; sin detalle de animal todavia, la pantalla deja elegir el animal.
  void _openHistory() => Navigator.of(context).push(clinicalHistoryRoute(context.read<AppDependencies>().sanitaryRepository));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final titles = [l10n.navClients, l10n.navCalendar, l10n.navProfile];
    final body = switch (_tab) {
      1 => MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: _upcoming),
            ChangeNotifierProvider.value(value: _calendar),
          ],
          child: const SanitaryCalendarPage(),
        ),
      2 => _ProfileTab(userName: widget.userName, onSignOut: widget.onSignOut),
      _ => EmptyView(message: l10n.comingSoon),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_tab]),
        actions: [
          if (_tab == 1) IconButton(onPressed: _openHistory, icon: const Icon(Icons.history), tooltip: l10n.historyAction),
        ],
      ),
      body: body,
      floatingActionButton: _tab == 1
          ? FloatingActionButton.extended(
              onPressed: _registerEvent,
              icon: const Icon(Icons.add),
              label: Text(l10n.registerEventAction),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _selectTab,
        destinations: [
          NavigationDestination(icon: const Icon(Icons.people_outline), label: l10n.navClients),
          NavigationDestination(icon: const Icon(Icons.calendar_month_outlined), label: l10n.navCalendar),
          NavigationDestination(icon: const Icon(Icons.person_outline), label: l10n.navProfile),
        ],
      ),
    );
  }
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab({required this.userName, required this.onSignOut});

  final String userName;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.profileGreeting(userName), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 24),
          OutlinedButton(onPressed: onSignOut, child: Text(l10n.signOut)),
        ],
      ),
    );
  }
}
