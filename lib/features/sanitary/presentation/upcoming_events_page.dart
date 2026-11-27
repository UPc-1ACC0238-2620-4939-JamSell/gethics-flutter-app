import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/state_views.dart';
import '../domain/upcoming_event.dart';
import 'upcoming_events_view_model.dart';

/// US-46: eventos sanitarios proximos y vencidos con su animal, fecha y etiqueta de urgencia.
class UpcomingEventsPage extends StatelessWidget {
  const UpcomingEventsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final viewModel = context.watch<UpcomingEventsViewModel>();
    final events = viewModel.events;

    if (viewModel.loading && events == null) return const LoadingView();
    if (events == null) {
      final message = viewModel.connectionError ? l10n.connectionError : viewModel.message;
      return ErrorView(message: message, onRetry: viewModel.load);
    }
    if (events.isEmpty) {
      return RefreshIndicator(
        onRefresh: viewModel.load,
        child: ListView(children: [
          SizedBox(
            height: 320,
            child: EmptyView(message: viewModel.message.isEmpty ? l10n.upcomingEmpty : viewModel.message),
          ),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: viewModel.load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (viewModel.needAttention > 0) ...[
            AttentionBanner(count: viewModel.needAttention),
            const SizedBox(height: 12),
          ],
          for (final event in events) ...[
            UpcomingEventCard(
              event: event,
              onReschedule: viewModel.rescheduling ? null : () => showRescheduleDialog(context, viewModel, event),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class AttentionBanner extends StatelessWidget {
  const AttentionBanner({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: GethicsColors.alertBackground, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: GethicsColors.alertText, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppLocalizations.of(context).upcomingNeedAttention(count),
              style: const TextStyle(color: GethicsColors.alertText),
            ),
          ),
        ],
      ),
    );
  }
}

String sanitaryTypeLabel(AppLocalizations l10n, SanitaryEventType type) => switch (type) {
      SanitaryEventType.vaccination => l10n.typeVaccination,
      SanitaryEventType.treatment => l10n.typeTreatment,
      SanitaryEventType.disease => l10n.typeDisease,
      SanitaryEventType.checkup => l10n.typeCheckup,
      SanitaryEventType.other => l10n.typeOther,
    };

String proximityLabel(AppLocalizations l10n, int daysUntil) {
  if (daysUntil < 0) return l10n.upcomingOverdueBy(-daysUntil);
  if (daysUntil == 0) return l10n.upcomingDueToday;
  return l10n.upcomingDueIn(daysUntil);
}

class UpcomingEventCard extends StatelessWidget {
  const UpcomingEventCard({super.key, required this.event, required this.onReschedule, this.showCancel = false, this.onCancel});

  final UpcomingEvent event;

  /// US-47: abre el dialogo de reprogramacion; null mientras otra reprogramacion esta en curso.
  final VoidCallback? onReschedule;

  /// US-33: la tarjeta ofrece cancelar el evento (la pantalla de solo alertas no lo hace).
  final bool showCancel;

  /// US-33: abre la confirmacion para cancelar el evento; null mientras hay otra accion en curso.
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final (badge, badgeColor, badgeBackground) = switch (event.urgency) {
      EventUrgency.overdue => (l10n.badgeOverdue, scheme.error, scheme.error.withValues(alpha: 0.1)),
      EventUrgency.urgent => (l10n.badgeUrgent, GethicsColors.alertText, GethicsColors.alertBackground),
      EventUrgency.upcoming => (l10n.badgeUpcoming, GethicsColors.inkVariant, GethicsColors.mint),
    };
    final date = DateFormat.yMMMd(locale).format(event.scheduledDate);

    return Card(
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: badgeBackground, borderRadius: BorderRadius.circular(8)),
                  child: Text(badge, style: TextStyle(color: badgeColor, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(event.animalLabel ?? l10n.unknownAnimal),
            const SizedBox(height: 2),
            Text(
              '$date · ${proximityLabel(l10n, event.daysUntil)}',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
            if (event.description != null) ...[
              const SizedBox(height: 2),
              Text(event.description!, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
            ],
            // Wrap: con dos acciones y texto grande o pantalla angosta, la segunda baja de linea en vez de desbordar.
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: onReschedule,
                    icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                    label: Text(l10n.rescheduleAction),
                  ),
                  if (showCancel)
                    TextButton.icon(
                      key: const Key('cancel-event'),
                      onPressed: onCancel,
                      style: TextButton.styleFrom(foregroundColor: scheme.error),
                      icon: const Icon(Icons.event_busy_outlined, size: 18),
                      label: Text(l10n.cancelEventAction),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// US-47: abre el dialogo para reprogramar [event]. Se cierra solo si el backend acepta la nueva fecha.
Future<void> showRescheduleDialog(BuildContext context, UpcomingEventsViewModel viewModel, UpcomingEvent event) {
  viewModel.clearRescheduleError();
  return showDialog<void>(
    context: context,
    builder: (_) => ChangeNotifierProvider.value(value: viewModel, child: RescheduleDialog(event: event)),
  );
}

/// US-47: nueva fecha (desde hoy; por defecto la actual si no vencio) y notas opcionales (por defecto las actuales).
/// La fecha y las notas viven en el dialogo, asi que un error del backend no borra lo ingresado.
class RescheduleDialog extends StatefulWidget {
  const RescheduleDialog({super.key, required this.event});

  final UpcomingEvent event;

  @override
  State<RescheduleDialog> createState() => _RescheduleDialogState();
}

class _RescheduleDialogState extends State<RescheduleDialog> {
  static const _notesMax = 1000; // mismo limite que valida el backend

  late DateTime _date;
  late final TextEditingController _notes;

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    _date = widget.event.scheduledDate.isBefore(_today) ? _today : widget.event.scheduledDate;
    _notes = TextEditingController(text: widget.event.description ?? '');
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: _today,
      lastDate: DateTime(_today.year + 5),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _confirm(UpcomingEventsViewModel viewModel) async {
    final navigator = Navigator.of(context);
    if (await viewModel.reschedule(widget.event, _date, _notes.text)) {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final viewModel = context.watch<UpcomingEventsViewModel>();
    final busy = viewModel.rescheduling;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final error = switch (viewModel.rescheduleError) {
      null => null,
      PastDateRescheduleError() => l10n.reschedulePastDate,
      ConnectionRescheduleError() => l10n.connectionError,
      ServerRescheduleError(:final serverMessage) => serverMessage.isEmpty ? l10n.rescheduleError : serverMessage,
    };

    return AlertDialog(
      title: Text(l10n.rescheduleTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.rescheduleDate, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            key: const Key('reschedule-date'),
            onPressed: busy ? null : _pickDate,
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Text(DateFormat.yMMMMd(locale).format(_date)),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('reschedule-notes'),
            controller: _notes,
            enabled: !busy,
            maxLength: _notesMax,
            decoration: InputDecoration(labelText: l10n.rescheduleNotes, counterText: ''),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.of(context).pop(), child: Text(l10n.cancel)),
        FilledButton(
          onPressed: busy ? null : () => _confirm(viewModel),
          child: busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l10n.rescheduleConfirm),
        ),
      ],
    );
  }
}

/// US-33: confirmacion para cancelar [event]. La accion destructiva (cancelar el evento) y la de conservarlo tienen
/// textos distintos y distintos del "Cancelar" que suele cerrar un dialogo. Se cierra solo si el backend cancela; el
/// aviso de exito se muestra en la pantalla de origen.
Future<void> showCancelEventDialog(BuildContext context, UpcomingEventsViewModel viewModel, UpcomingEvent event) async {
  final messenger = ScaffoldMessenger.of(context);
  final successMessage = AppLocalizations.of(context).cancelEventSuccess;
  viewModel.clearCancelError();
  final cancelled = await showDialog<bool>(
    context: context,
    builder: (_) => ChangeNotifierProvider.value(value: viewModel, child: CancelEventDialog(event: event)),
  );
  if (cancelled == true) messenger.showSnackBar(SnackBar(content: Text(successMessage)));
}

class CancelEventDialog extends StatelessWidget {
  const CancelEventDialog({super.key, required this.event});

  final UpcomingEvent event;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final viewModel = context.watch<UpcomingEventsViewModel>();
    final busy = viewModel.busy;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final error = switch (viewModel.cancelError) {
      null => null,
      ConnectionCancelError() => l10n.connectionError,
      ServerCancelError(:final serverMessage) => serverMessage.isEmpty ? l10n.cancelEventError : serverMessage,
    };

    // Mientras se envia no se puede cerrar tocando fuera: el resultado se perderia.
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: Text(l10n.cancelEventTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${sanitaryTypeLabel(l10n, event.type)} · ${event.animalLabel ?? l10n.unknownAnimal}\n'
                '${DateFormat.yMMMd(locale).format(event.scheduledDate)}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text(l10n.cancelEventMessage),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error, style: TextStyle(color: scheme.error)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const Key('cancel-keep'),
            onPressed: busy ? null : () => Navigator.of(context).pop(false),
            child: Text(l10n.cancelEventKeep),
          ),
          FilledButton(
            key: const Key('cancel-confirm'),
            style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
            onPressed: busy ? null : () => _confirm(context, viewModel),
            child: busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l10n.cancelEventAction),
          ),
        ],
      ),
    );
  }

  Future<void> _confirm(BuildContext context, UpcomingEventsViewModel viewModel) async {
    final navigator = Navigator.of(context);
    if (await viewModel.cancelEvent(event)) navigator.pop(true);
  }
}
