import 'package:material_ui/material_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/state_views.dart';

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final titles = [l10n.navClients, l10n.navCalendar, l10n.navProfile];
    final body = switch (_tab) {
      2 => _ProfileTab(userName: widget.userName, onSignOut: widget.onSignOut),
      _ => EmptyView(message: l10n.comingSoon),
    };
    return Scaffold(
      appBar: AppBar(title: Text(titles[_tab])),
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
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
