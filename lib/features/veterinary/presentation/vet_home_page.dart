import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/di/app_dependencies.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/state_views.dart';
import '../../livestock/presentation/animal_detail_page.dart';
import '../../livestock/presentation/animal_list_page.dart';
import '../../livestock/presentation/animal_list_view_model.dart';
import '../../sanitary/data/sanitary_sync_service.dart';
import '../../sanitary/presentation/clinical_history_page.dart';
import '../../sanitary/presentation/register_event_page.dart';
import '../../sanitary/presentation/sanitary_calendar_page.dart';
import '../../sanitary/presentation/sanitary_calendar_view_model.dart';
import '../../sanitary/presentation/upcoming_events_view_model.dart';

/// Inicio del flujo veterinario: navegacion inferior con Clientes, Calendario, Animales y Perfil. Las pestanas sin historia
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

  // US-42: listado de animales; se crea una vez para conservar busqueda y filtros, y carga al abrir Animales.
  late final AnimalListViewModel _animals;
  bool _animalsLoaded = false;

  @override
  void initState() {
    super.initState();
    final repository = context.read<AppDependencies>().sanitaryRepository;
    _animals = AnimalListViewModel(context.read<AppDependencies>().livestockRepository);
    _calendar = SanitaryCalendarViewModel(repository);
    // Reprogramar mueve el evento de mes: el calendario mensual se recarga junto con las alertas.
    _upcoming = UpcomingEventsViewModel(repository, onEventsChanged: _calendar.load);
  }

  @override
  void dispose() {
    _upcoming.dispose();
    _calendar.dispose();
    _animals.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    setState(() => _tab = index);
    if (index == 1 && !_upcomingLoaded) {
      _upcomingLoaded = true;
      _upcoming.load();
      _calendar.load();
    }
    if (index == 2 && !_animalsLoaded) {
      _animalsLoaded = true;
      _animals.load();
    }
  }

  // US-11: formulario de registro; sin detalle de animal todavia, el formulario deja elegir el animal.
  // US-35: sin conexion el formulario se cierra con queued y se avisa que se sincronizara despues.
  Future<void> _registerEvent() async {
    final result = await Navigator.of(context).push(registerEventRoute(context.read<AppDependencies>().sanitaryRepository));
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final message = saveResultMessage(l10n, result, sentMessage: l10n.registerEventSuccess);
    if (message != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // US-13: programa una vacuna; el evento nuevo aparece en el calendario y en las alertas, asi que se recargan. Una
  // guardada sin conexion (US-35) aun no esta en el backend: no se recarga nada.
  Future<void> _scheduleVaccination() async {
    final result = await Navigator.of(context).push(scheduleVaccinationRoute(context.read<AppDependencies>().sanitaryRepository));
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final message = saveResultMessage(l10n, result, sentMessage: l10n.scheduleVaccinationSuccess);
    if (message != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    if (result == SanitarySaveResult.sent) {
      _upcoming.load();
      _calendar.load();
    }
  }

  // US-14: historial clinico; sin detalle de animal todavia, la pantalla deja elegir el animal.
  void _openHistory() => Navigator.of(context).push(clinicalHistoryRoute(context.read<AppDependencies>().sanitaryRepository));

  // US-43: ficha del animal elegido en el listado, con su granja y el acceso a su historial clinico.
  void _openAnimal(String animalId) {
    final dependencies = context.read<AppDependencies>();
    Navigator.of(context).push(animalDetailRoute(dependencies.livestockRepository, dependencies.sanitaryRepository, animalId));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final titles = [l10n.navClients, l10n.navCalendar, l10n.navAnimals, l10n.navProfile];
    final body = switch (_tab) {
      1 => MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: _upcoming),
            ChangeNotifierProvider.value(value: _calendar),
          ],
          child: const SanitaryCalendarPage(),
        ),
      2 => ChangeNotifierProvider.value(value: _animals, child: AnimalListPage(onOpenAnimal: _openAnimal)),
      3 => _ProfileTab(userName: widget.userName, onSignOut: widget.onSignOut),
      _ => EmptyView(message: l10n.comingSoon),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_tab]),
        actions: [
          if (_tab == 1) ...[
            IconButton(
              key: const Key('schedule-vaccination'),
              onPressed: _scheduleVaccination,
              icon: const Icon(Icons.vaccines_outlined),
              tooltip: l10n.scheduleVaccinationTitle,
            ),
            IconButton(onPressed: _openHistory, icon: const Icon(Icons.history), tooltip: l10n.historyAction),
          ],
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
          NavigationDestination(icon: const Icon(Icons.pets_outlined), label: l10n.navAnimals),
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
