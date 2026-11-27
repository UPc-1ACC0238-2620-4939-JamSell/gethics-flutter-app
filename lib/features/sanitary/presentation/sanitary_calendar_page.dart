import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/state_views.dart';
import '../domain/upcoming_event.dart';
import 'sanitary_calendar_view_model.dart';
import 'upcoming_events_page.dart';
import 'upcoming_events_view_model.dart';

/// Pestana Calendario: arriba las alertas de eventos proximos y vencidos (US-46, con Reprogramar de US-47) y debajo el
/// calendario del mes (US-12) con navegacion entre meses. Las alertas no dependen del mes que se consulte. Las dos
/// secciones comparten la misma tarjeta y el mismo dialogo de reprogramacion; tirar para actualizar recarga ambas.
class SanitaryCalendarPage extends StatelessWidget {
  const SanitaryCalendarPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final upcoming = context.watch<UpcomingEventsViewModel>();
    final calendar = context.watch<SanitaryCalendarViewModel>();
    return RefreshIndicator(
      onRefresh: () => Future.wait([upcoming.load(), calendar.load()]),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.upcomingTitle, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ..._alerts(context, l10n, upcoming),
          const SizedBox(height: 16),
          _MonthSelector(calendar: calendar),
          const SizedBox(height: 8),
          ..._month(context, l10n, calendar, upcoming),
        ],
      ),
    );
  }

  /// Mismos estados que UpcomingEventsPage (US-46), pero dentro de la lista para no ocultar el calendario.
  List<Widget> _alerts(BuildContext context, AppLocalizations l10n, UpcomingEventsViewModel upcoming) {
    final events = upcoming.events;
    if (events == null) {
      if (upcoming.loading) return const [SizedBox(height: 96, child: LoadingView())];
      return [
        SizedBox(
          height: 180,
          child: ErrorView(message: upcoming.connectionError ? l10n.connectionError : upcoming.message, onRetry: upcoming.load),
        ),
      ];
    }
    if (events.isEmpty) {
      return [SizedBox(height: 96, child: EmptyView(message: upcoming.message.isEmpty ? l10n.upcomingEmpty : upcoming.message))];
    }
    return [
      if (upcoming.needAttention > 0) ...[AttentionBanner(count: upcoming.needAttention), const SizedBox(height: 12)],
      for (final event in events) ...[
        UpcomingEventCard(
          event: event,
          onReschedule: _rescheduleAction(context, upcoming, event),
          showCancel: true,
          onCancel: _cancelAction(context, upcoming, event),
        ),
        const SizedBox(height: 12),
      ],
    ];
  }

  VoidCallback? _rescheduleAction(BuildContext context, UpcomingEventsViewModel upcoming, UpcomingEvent event) =>
      upcoming.busy ? null : () => showRescheduleDialog(context, upcoming, event);

  VoidCallback? _cancelAction(BuildContext context, UpcomingEventsViewModel upcoming, UpcomingEvent event) =>
      upcoming.busy ? null : () => showCancelEventDialog(context, upcoming, event);

  List<Widget> _month(
    BuildContext context,
    AppLocalizations l10n,
    SanitaryCalendarViewModel calendar,
    UpcomingEventsViewModel upcoming,
  ) {
    final events = calendar.events;
    if (events == null) {
      if (calendar.loading) return const [SizedBox(height: 160, child: LoadingView())];
      return [
        SizedBox(
          height: 180,
          child: ErrorView(message: calendar.connectionError ? l10n.connectionError : calendar.message, onRetry: calendar.load),
        ),
      ];
    }
    if (events.isEmpty) return [SizedBox(height: 160, child: EmptyView(message: l10n.calendarMonthEmpty))];

    final locale = Localizations.localeOf(context).toLanguageTag();
    final children = <Widget>[];
    DateTime? currentDay;
    for (final event in events) {
      final day = event.scheduledDate;
      if (currentDay == null || day != currentDay) {
        currentDay = day;
        children.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Semantics(
            header: true,
            child: Text(
              toBeginningOfSentenceCase(DateFormat.MMMEd(locale).format(day), locale),
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ));
      }
      children
        ..add(UpcomingEventCard(
          event: event,
          onReschedule: _rescheduleAction(context, upcoming, event),
          showCancel: true,
          onCancel: _cancelAction(context, upcoming, event),
        ))
        ..add(const SizedBox(height: 12));
    }
    return children;
  }
}

/// Mes y anio en el idioma activo con botones de 48 dp para ir al mes anterior y al siguiente. Nunca se deshabilitan:
/// un error o una carga en curso no impiden cambiar de mes.
class _MonthSelector extends StatelessWidget {
  const _MonthSelector({required this.calendar});

  final SanitaryCalendarViewModel calendar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final label = toBeginningOfSentenceCase(DateFormat.yMMMM(locale).format(calendar.month), locale);
    return Row(
      children: [
        IconButton(
          key: const Key('calendar-previous'),
          onPressed: calendar.previousMonth,
          icon: const Icon(Icons.chevron_left),
          tooltip: l10n.calendarPreviousMonth,
        ),
        Expanded(
          child: Semantics(
            header: true,
            liveRegion: true, // el lector de pantalla anuncia el mes nuevo
            child: Text(
              label,
              key: const Key('calendar-month'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
        IconButton(
          key: const Key('calendar-next'),
          onPressed: calendar.nextMonth,
          icon: const Icon(Icons.chevron_right),
          tooltip: l10n.calendarNextMonth,
        ),
      ],
    );
  }
}
