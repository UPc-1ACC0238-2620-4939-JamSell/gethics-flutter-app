import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/sanitary_repository.dart';
import '../domain/animal_option.dart';
import '../domain/clinical_history.dart';
import 'clinical_history_view_model.dart';
import 'register_event_page.dart';
import 'upcoming_events_page.dart' show sanitaryTypeLabel;

/// US-14: ruta del historial clinico de un animal. Con [animal] (p. ej. desde el detalle de un animal) abre su
/// historial directamente; sin el, deja elegir uno de los animales activos.
Route<void> clinicalHistoryRoute(SanitaryRepository repository, {AnimalOption? animal}) {
  return MaterialPageRoute<void>(
    builder: (_) => ChangeNotifierProvider(
      create: (_) => ClinicalHistoryViewModel(repository, animal: animal)
        ..loadAnimals()
        ..load(),
      child: ClinicalHistoryPage(repository: repository),
    ),
  );
}

class ClinicalHistoryPage extends StatelessWidget {
  const ClinicalHistoryPage({super.key, required this.repository});

  /// Para abrir el registro de un evento (US-11) del animal que se esta consultando.
  final SanitaryRepository repository;

  Future<void> _registerEvent(BuildContext context, ClinicalHistoryViewModel viewModel) async {
    final messenger = ScaffoldMessenger.of(context);
    final message = AppLocalizations.of(context).registerEventSuccess;
    final saved = await Navigator.of(context).push(registerEventRoute(repository, animal: viewModel.animal));
    if (saved == true) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
      await viewModel.load(); // el evento recien registrado ya aparece en el historial
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final viewModel = context.watch<ClinicalHistoryViewModel>();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.historyTitle)),
      body: _body(context, l10n, viewModel),
      floatingActionButton: viewModel.animal == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _registerEvent(context, viewModel),
              icon: const Icon(Icons.add),
              label: Text(l10n.registerEventAction),
            ),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n, ClinicalHistoryViewModel viewModel) {
    final animals = viewModel.animals;
    if (!viewModel.lockedAnimal) {
      if (animals == null) {
        if (viewModel.loadingAnimals) return const LoadingView();
        return ErrorView(
          message: viewModel.animalsConnectionError ? l10n.connectionError : viewModel.animalsMessage,
          onRetry: viewModel.loadAnimals,
        );
      }
      if (animals.isEmpty) return EmptyView(message: l10n.registerEventNoAnimals);
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: viewModel.lockedAnimal
              ? Row(children: [
                  const Icon(Icons.pets_outlined, color: GethicsColors.inkVariant),
                  const SizedBox(width: 8),
                  Expanded(child: Text(viewModel.animal!.label, style: Theme.of(context).textTheme.titleMedium)),
                ])
              : DropdownButtonFormField<AnimalOption>(
                  key: const Key('history-animal'),
                  initialValue: viewModel.animal == null
                      ? null
                      : animals!.where((a) => a.id == viewModel.animal!.id).firstOrNull,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l10n.registerEventAnimal),
                  items: [
                    for (final animal in animals!)
                      DropdownMenuItem(value: animal, child: Text(animal.label, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: viewModel.selectAnimal,
                ),
        ),
        Expanded(child: _history(context, l10n, viewModel)),
      ],
    );
  }

  Widget _history(BuildContext context, AppLocalizations l10n, ClinicalHistoryViewModel viewModel) {
    final history = viewModel.history;
    if (viewModel.animal == null) return EmptyView(message: l10n.historySelectAnimal);
    if (viewModel.loading && history == null) return const LoadingView();
    if (history == null) {
      return ErrorView(
        message: viewModel.connectionError ? l10n.connectionError : viewModel.message,
        onRetry: viewModel.load,
      );
    }
    if (history.events.isEmpty) {
      // El texto del backend ("Sin registros.") va siempre en espanol: se usa el de la app, en el idioma activo.
      return RefreshIndicator(
        onRefresh: viewModel.load,
        child: ListView(children: [SizedBox(height: 320, child: EmptyView(message: l10n.historyEmpty))]),
      );
    }
    final events = history.events; // orden del backend: del mas antiguo al mas reciente
    return RefreshIndicator(
      onRefresh: viewModel.load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 88), // el espacio final deja ver la ultima tarjeta tras el boton
        itemCount: events.length,
        itemBuilder: (context, index) => _TimelineItem(event: events[index], isLast: index == events.length - 1),
      ),
    );
  }
}

/// Color del estado: realizado en verde de Gethics, programado en ambar, cancelado en rojo.
(String, Color, Color) _statusStyle(AppLocalizations l10n, ColorScheme scheme, SanitaryEventStatus status) =>
    switch (status) {
      SanitaryEventStatus.completed => (l10n.historyStatusCompleted, GethicsColors.inkVariant, GethicsColors.mint),
      SanitaryEventStatus.scheduled => (l10n.historyStatusScheduled, GethicsColors.alertText, GethicsColors.alertBackground),
      SanitaryEventStatus.cancelled => (l10n.historyStatusCancelled, scheme.error, scheme.error.withValues(alpha: 0.1)),
    };

/// Marcador + conector de la linea de tiempo y la tarjeta del evento.
class _TimelineItem extends StatelessWidget {
  const _TimelineItem({required this.event, required this.isLast});

  final ClinicalHistoryEvent event;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final status = event.status;
    final style = status == null ? null : _statusStyle(l10n, scheme, status);
    final markerColor = style?.$2 ?? GethicsColors.inkVariant;
    final date = event.displayDate;
    final dateText = date == null ? l10n.historyNoDate : DateFormat.yMMMd(locale).format(date);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 20,
            child: Column(
              children: [
                const SizedBox(height: 18),
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: markerColor, width: 2),
                    // Realizado: marcador lleno; programado y cancelado: solo el borde.
                    color: status == SanitaryEventStatus.completed ? markerColor : Colors.transparent,
                  ),
                ),
                if (!isLast) Expanded(child: Container(width: 1, color: const Color(0xFFE2E7DF))),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
              child: Card(
                margin: EdgeInsets.zero,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: const BorderSide(color: Color(0xFFE2E7DF)),
                ),
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              sanitaryTypeLabel(l10n, event.type),
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (style != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: style.$3, borderRadius: BorderRadius.circular(8)),
                              child: Text(
                                style.$1,
                                style: TextStyle(color: style.$2, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(dateText, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                      if (event.description != null) ...[
                        const SizedBox(height: 6),
                        Text(event.description!),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
