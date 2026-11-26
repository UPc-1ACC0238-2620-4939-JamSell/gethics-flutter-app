/// Tipos de evento sanitario del backend (SanitaryEventType).
enum SanitaryEventType {
  vaccination,
  treatment,
  disease,
  checkup,
  other;

  /// Tipo desconocido o sin dato: other, para no ocultar el evento.
  static SanitaryEventType fromName(String? value) => SanitaryEventType.values
      .firstWhere((type) => type.name.toUpperCase() == value?.toUpperCase(), orElse: () => SanitaryEventType.other);
}

/// US-46: hasta cuantos dias antes un evento se marca como urgente.
const int urgentWithinDays = 2;

/// US-46: ventana de alerta, la misma que usa el backend por defecto.
const int upcomingWindowDays = 7;

/// Nivel de proximidad que la pantalla traduce a color y texto.
enum EventUrgency { overdue, urgent, upcoming }

EventUrgency urgencyOf(int daysUntil, {required bool overdue}) {
  if (overdue || daysUntil < 0) return EventUrgency.overdue;
  if (daysUntil <= urgentWithinDays) return EventUrgency.urgent;
  return EventUrgency.upcoming;
}

/// Evento programado proximo o vencido (UpcomingSanitaryEventResource) con el nombre del animal ya resuelto.
class UpcomingEvent {
  const UpcomingEvent({
    required this.id,
    required this.animalId,
    required this.animalLabel,
    required this.type,
    required this.scheduledDate,
    required this.description,
    required this.daysUntil,
    required this.urgency,
  });

  final String id;
  final String animalId;

  /// Nombre o arete del animal; null si no se pudo resolver.
  final String? animalLabel;
  final SanitaryEventType type;
  final DateTime scheduledDate;
  final String? description;
  final int daysUntil;
  final EventUrgency urgency;
}

/// Respuesta de GET /api/v1/sanitary-events/upcoming. [message] solo viene con la lista vacia.
class UpcomingEvents {
  const UpcomingEvents({required this.events, required this.message});

  final List<UpcomingEvent> events;
  final String message;
}
