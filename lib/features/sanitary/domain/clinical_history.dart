import 'upcoming_event.dart' show SanitaryEventType;

/// Estados de un evento sanitario del backend (SanitaryEventStatus).
enum SanitaryEventStatus {
  scheduled,
  completed,
  cancelled;

  /// Estado desconocido o sin dato: null, para no mostrarle al veterinario un estado inventado.
  static SanitaryEventStatus? fromName(String? value) {
    for (final status in values) {
      if (status.name.toUpperCase() == value?.toUpperCase()) return status;
    }
    return null;
  }
}

/// US-14: un evento del historial (ClinicalHistoryEventResource). [occurredAt] solo viene en los realizados;
/// [scheduledDate] en los programados y cancelados (y en un realizado que antes estuvo programado).
class ClinicalHistoryEvent {
  const ClinicalHistoryEvent({
    required this.id,
    required this.type,
    required this.status,
    required this.occurredAt,
    required this.scheduledDate,
    required this.description,
  });

  final String id;
  final SanitaryEventType type;
  final SanitaryEventStatus? status;
  final DateTime? occurredAt;
  final DateTime? scheduledDate;
  final String? description;

  /// Fecha a mostrar, con la misma regla con la que el backend ordena: realizado -> occurredAt; programado o
  /// cancelado -> scheduledDate. null si no hay una fecha utilizable: no se inventa ninguna.
  DateTime? get displayDate => switch (status) {
        SanitaryEventStatus.completed => occurredAt,
        SanitaryEventStatus.scheduled || SanitaryEventStatus.cancelled => scheduledDate,
        null => null,
      };
}

/// Respuesta de GET /api/v1/animals/{animalId}/clinical-history. Los eventos llegan en orden cronologico ascendente
/// (del mas antiguo al mas reciente); [message] solo trae valor con la lista vacia ("Sin registros.").
class ClinicalHistory {
  const ClinicalHistory({required this.animalId, required this.events, required this.message});

  final String animalId;
  final List<ClinicalHistoryEvent> events;
  final String message;
}
