import '../../../core/common/result.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../domain/upcoming_event.dart';

/// Acceso a los Web Services del contexto sanitary.
class SanitaryRepository {
  SanitaryRepository(this._api);

  final ApiClient _api;

  /// US-46: eventos que vencen en los proximos [days] dias, mas los vencidos que siguen pendientes, con el nombre o
  /// arete de su animal. Si no se pueden leer los animales, los eventos se devuelven igual sin nombre.
  Future<Result<UpcomingEvents>> getUpcomingEvents({int days = upcomingWindowDays}) async {
    try {
      final json = await _api.get('api/v1/sanitary-events/upcoming', query: {'days': '$days'}) as Map<String, dynamic>;
      final items = (json['events'] as List<dynamic>).cast<Map<String, dynamic>>();
      final names = items.isEmpty ? const <String, String>{} : await _animalNames();
      final events = items.map((e) => _toEvent(e, names)).toList();
      return Success(UpcomingEvents(events: events, message: events.isEmpty ? (json['message'] as String? ?? '') : ''));
    } on ApiException catch (e) {
      return Failure(e.message, isConnectionError: e.isConnectionError);
    }
  }

  /// US-47: cambia la fecha (y, si se envian, las notas) de un evento programado. [description] null conserva las
  /// notas actuales. El backend responde 400 (fecha anterior a hoy), 404 o 409 (el evento ya no esta pendiente).
  Future<Result<void>> rescheduleEvent({
    required String animalId,
    required String eventId,
    required DateTime scheduledDate,
    String? description,
  }) async {
    try {
      await _api.post('api/v1/animals/$animalId/sanitary-events/$eventId/reschedule', body: {
        'scheduledDate': _isoDate(scheduledDate),
        'description': description,
      });
      return const Success(null);
    } on ApiException catch (e) {
      return Failure(e.message, isConnectionError: e.isConnectionError);
    }
  }

  static String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  /// animalId -> nombre (o arete si no tiene nombre) de los animales activos.
  Future<Map<String, String>> _animalNames() async {
    try {
      final json = await _api.get('api/v1/animals', query: {'status': 'ACTIVE'}) as Map<String, dynamic>;
      return {
        for (final animal in (json['animals'] as List<dynamic>).cast<Map<String, dynamic>>())
          animal['id'] as String: (animal['name'] as String?)?.trim().isNotEmpty == true
              ? animal['name'] as String
              : animal['tag'] as String? ?? '',
      };
    } on ApiException {
      return const {};
    }
  }

  static UpcomingEvent _toEvent(Map<String, dynamic> json, Map<String, String> names) {
    final daysUntil = (json['daysUntil'] as num).toInt();
    final description = (json['description'] as String?)?.trim();
    return UpcomingEvent(
      id: json['id'] as String,
      animalId: json['animalId'] as String,
      animalLabel: names[json['animalId']],
      type: SanitaryEventType.fromName(json['type'] as String?),
      scheduledDate: DateTime.parse(json['scheduledDate'] as String),
      description: description == null || description.isEmpty ? null : description,
      daysUntil: daysUntil,
      urgency: urgencyOf(daysUntil, overdue: json['overdue'] as bool? ?? false),
    );
  }
}
