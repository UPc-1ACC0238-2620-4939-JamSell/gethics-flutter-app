import '../../../core/common/result.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../domain/animal_option.dart';
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

  /// US-11: registra un evento ya ocurrido (el backend lo guarda COMPLETED). [occurredAt] se envia como fecha a las
  /// 00:00:00, asi que hoy nunca cuenta como futuro. [clientRequestId] (UUID) hace el registro idempotente: repetir el
  /// mismo id con los mismos datos devuelve el evento existente (200) y con otros datos es 409. El backend responde
  /// 201/200, 400 (campos o fecha posterior a hoy) o 409.
  Future<Result<void>> registerEvent({
    required String animalId,
    required SanitaryEventType type,
    required DateTime occurredAt,
    String? description,
    required String clientRequestId,
  }) async {
    try {
      await _api.post('api/v1/animals/$animalId/sanitary-events', body: {
        'type': type.name.toUpperCase(),
        'occurredAt': '${_isoDate(occurredAt)}T00:00:00',
        'description': ?description,
        'clientRequestId': clientRequestId,
      });
      return const Success(null);
    } on ApiException catch (e) {
      return Failure(e.message, isConnectionError: e.isConnectionError);
    }
  }

  /// US-11: animales activos para elegir a cual se le registra el evento.
  Future<Result<List<AnimalOption>>> getAnimals() async {
    try {
      final json = await _api.get('api/v1/animals', query: {'status': 'ACTIVE'}) as Map<String, dynamic>;
      return Success([
        for (final animal in (json['animals'] as List<dynamic>).cast<Map<String, dynamic>>())
          AnimalOption(id: animal['id'] as String, label: _animalLabel(animal)),
      ]);
    } on ApiException catch (e) {
      return Failure(e.message, isConnectionError: e.isConnectionError);
    }
  }

  static String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  /// Nombre del animal o, si no tiene, su arete.
  static String _animalLabel(Map<String, dynamic> animal) =>
      (animal['name'] as String?)?.trim().isNotEmpty == true ? animal['name'] as String : animal['tag'] as String? ?? '';

  /// animalId -> nombre (o arete si no tiene nombre) de los animales activos.
  Future<Map<String, String>> _animalNames() async {
    try {
      final json = await _api.get('api/v1/animals', query: {'status': 'ACTIVE'}) as Map<String, dynamic>;
      return {
        for (final animal in (json['animals'] as List<dynamic>).cast<Map<String, dynamic>>())
          animal['id'] as String: _animalLabel(animal),
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
