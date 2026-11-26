import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/di/app_dependencies.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/state_views.dart';
import '../../sanitary/presentation/upcoming_events_page.dart';
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

  // US-46: se crea una vez para conservar la lista al cambiar de pestana; carga al abrir la pestana Calendario.
  late final UpcomingEventsViewModel _upcoming;
  bool _upcomingLoaded = false;

  @override
  void initState() {
    super.initState();
    _upcoming = UpcomingEventsViewModel(context.read<AppDependencies>().sanitaryRepository);
  }

  @override
  void dispose() {
    _upcoming.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    setState(() => _tab = index);
    if (index == 1 && !_upcomingLoaded) {
      _upcomingLoaded = true;
      _upcoming.load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final titles = [l10n.navClients, l10n.upcomingTitle, l10n.navProfile];
    final body = switch (_tab) {
      1 => ChangeNotifierProvider.value(value: _upcoming, child: const UpcomingEventsPage()),
      2 => _ProfileTab(userName: widget.userName, onSignOut: widget.onSignOut),
      _ => EmptyView(message: l10n.comingSoon),
    };
    return Scaffold(
      appBar: AppBar(title: Text(titles[_tab])),
      body: body,
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
