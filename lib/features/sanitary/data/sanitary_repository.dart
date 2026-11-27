import '../../../core/common/result.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../domain/animal_option.dart';
import '../domain/clinical_history.dart';
import '../domain/upcoming_event.dart';
import 'pending_sanitary_store.dart';
import 'sanitary_sync_service.dart';

/// Acceso a los Web Services del contexto sanitary.
///
/// [offline] (US-35): con el, registrar y programar se guardan en la cola del dispositivo antes de enviarse y, sin
/// conexion, quedan pendientes (Success(queued)). Sin el (pruebas de otras historias) se envian directo como antes.
class SanitaryRepository {
  SanitaryRepository(this._api, {SanitarySyncService? offline}) : _offline = offline; // ignore: prefer_initializing_formals

  final ApiClient _api;
  final SanitarySyncService? _offline;

  // US-35: ultima lista de animales leida en esta ejecucion y de que usuario es; sin conexion el formulario la usa.
  ({String userId, List<AnimalOption> animals})? _lastAnimals;

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

  /// US-13: programa una vacunacion (evento VACCINATION en estado SCHEDULED). El backend rechaza con 400 una fecha
  /// anterior a hoy. Su job diario genera el recordatorio 3 dias antes de la fecha; hoy ese envio solo queda en el log
  /// del servidor (no hay push real), asi que esta app no promete una notificacion. [clientRequestId] (UUID) hace el
  /// registro idempotente: el mismo id con los mismos datos devuelve el evento existente (200). Con [_offline], sin
  /// conexion queda en la cola (US-35).
  Future<Result<SanitarySaveResult>> scheduleVaccination({
    required String animalId,
    required DateTime scheduledDate,
    String? description,
    required String clientRequestId,
  }) =>
      _create(SanitaryRequest(
        operation: SanitaryOperation.schedule,
        animalId: animalId,
        type: SanitaryEventType.vaccination,
        date: _isoDate(scheduledDate),
        description: description,
        clientRequestId: clientRequestId,
      ));

  Future<Result<SanitarySaveResult>> _create(SanitaryRequest request) async {
    final offline = _offline;
    if (offline != null) return offline.save(request);
    try {
      await _api.post(request.path, body: request.body);
      return const Success(SanitarySaveResult.sent);
    } on ApiException catch (e) {
      return Failure(e.message, isConnectionError: e.isConnectionError);
    }
  }

  /// US-13: registra como aplicado el MISMO evento programado (SCHEDULED -> COMPLETED); no crea otro. [occurredAt] va
  /// a las 00:00:00 como en US-11 y no puede ser posterior a hoy (400). Sin description el backend conserva la de la
  /// programacion. Responde 404 (el animal no tiene ese evento) o 409 (ya no esta programado).
  Future<Result<void>> completeEvent({
    required String animalId,
    required String eventId,
    required DateTime occurredAt,
  }) async {
    try {
      await _api.post('api/v1/animals/$animalId/sanitary-events/$eventId/complete', body: {
        'occurredAt': '${_isoDate(occurredAt)}T00:00:00',
      });
      return const Success(null);
    } on ApiException catch (e) {
      return Failure(e.message, isConnectionError: e.isConnectionError);
    }
  }

  /// US-33: cancela un evento programado (SCHEDULED -> CANCELLED); el backend no lo borra, queda en el historial
  /// clinico. La solicitud no lleva cuerpo. Responde 200, 400 (id invalido), 404 (el animal no tiene ese evento) o 409
  /// (el evento ya no esta programado: completado o cancelado).
  Future<Result<void>> cancelEvent({required String animalId, required String eventId}) async {
    try {
      await _api.post('api/v1/animals/$animalId/sanitary-events/$eventId/cancel');
      return const Success(null);
    } on ApiException catch (e) {
      return Failure(e.message, isConnectionError: e.isConnectionError);
    }
  }

  /// US-11: registra un evento ya ocurrido (el backend lo guarda COMPLETED). [occurredAt] se envia como fecha a las
  /// 00:00:00, asi que hoy nunca cuenta como futuro. [clientRequestId] (UUID) hace el registro idempotente: repetir el
  /// mismo id con los mismos datos devuelve el evento existente (200) y con otros datos es 409. El backend responde
  /// 201/200, 400 (campos o fecha posterior a hoy) o 409. Con [_offline], sin conexion queda en la cola (US-35).
  Future<Result<SanitarySaveResult>> registerEvent({
    required String animalId,
    required SanitaryEventType type,
    required DateTime occurredAt,
    String? description,
    required String clientRequestId,
  }) =>
      _create(SanitaryRequest(
        operation: SanitaryOperation.register,
        animalId: animalId,
        type: type,
        date: '${_isoDate(occurredAt)}T00:00:00',
        description: description,
        clientRequestId: clientRequestId,
      ));

  /// US-11: animales activos para elegir a cual se le registra el evento. US-35: sin conexion devuelve la ultima lista
  /// que este mismo usuario leyo en esta ejecucion de la app (no se guarda en disco; eso es US-36).
  Future<Result<List<AnimalOption>>> getAnimals() async {
    try {
      final json = await _api.get('api/v1/animals', query: {'status': 'ACTIVE'}) as Map<String, dynamic>;
      final animals = [
        for (final animal in (json['animals'] as List<dynamic>).cast<Map<String, dynamic>>())
          AnimalOption(id: animal['id'] as String, label: _animalLabel(animal)),
      ];
      final userId = _offline?.userId;
      _lastAnimals = userId == null ? null : (userId: userId, animals: animals);
      return Success(animals);
    } on ApiException catch (e) {
      final last = _lastAnimals;
      if (e.isConnectionError && last != null && last.userId == _offline?.userId) return Success(last.animals);
      return Failure(e.message, isConnectionError: e.isConnectionError);
    }
  }

  /// US-12: eventos programados (SCHEDULED) del mes, en el orden del backend (por fecha). El endpoint no envia
  /// daysUntil ni overdue: se calculan con [today] para reutilizar el mismo modelo y tarjeta que US-46. [names] es
  /// animalId -> nombre (ver [getAnimalNames]). El backend responde 400 con un mes fuera de 1-12 o un anio fuera de rango.
  Future<Result<List<UpcomingEvent>>> getCalendar({
    required int year,
    required int month,
    required DateTime today,
    Map<String, String> names = const {},
  }) async {
    try {
      final json = await _api.get('api/v1/sanitary-calendar', query: {'year': '$year', 'month': '$month'})
          as Map<String, dynamic>;
      final items = ((json['events'] as List<dynamic>?) ?? const []).cast<Map<String, dynamic>>();
      return Success([
        for (final item in items)
          if ((item['status'] as String? ?? 'SCHEDULED').toUpperCase() == 'SCHEDULED') _toCalendarEvent(item, names, today),
      ]);
    } on ApiException catch (e) {
      return Failure(e.message, isConnectionError: e.isConnectionError);
    }
  }

  /// animalId -> nombre (o arete) de los animales activos; vacio si no se pueden leer.
  Future<Map<String, String>> getAnimalNames() => _animalNames();

  static UpcomingEvent _toCalendarEvent(Map<String, dynamic> json, Map<String, String> names, DateTime today) {
    final scheduled = DateTime.parse(json['scheduledDate'] as String);
    // Dias de calendario (en UTC para que el cambio de horario no mueva el resultado).
    final daysUntil = DateTime.utc(scheduled.year, scheduled.month, scheduled.day)
        .difference(DateTime.utc(today.year, today.month, today.day))
        .inDays;
    final description = (json['description'] as String?)?.trim();
    return UpcomingEvent(
      id: json['id'] as String,
      animalId: json['animalId'] as String,
      animalLabel: names[json['animalId']],
      type: SanitaryEventType.fromName(json['type'] as String?),
      scheduledDate: scheduled,
      description: description == null || description.isEmpty ? null : description,
      daysUntil: daysUntil,
      urgency: urgencyOf(daysUntil, overdue: daysUntil < 0),
    );
  }

  /// US-14: historial clinico del animal (todos sus eventos, tambien programados y cancelados), en el orden del
  /// backend. Un animal sin eventos responde 200 con la lista vacia; un animalId invalido, 400.
  Future<Result<ClinicalHistory>> getClinicalHistory(String animalId) async {
    try {
      final json = await _api.get('api/v1/animals/$animalId/clinical-history') as Map<String, dynamic>;
      final items = ((json['events'] as List<dynamic>?) ?? const []).cast<Map<String, dynamic>>();
      return Success(ClinicalHistory(
        animalId: json['animalId'] as String? ?? animalId,
        events: items.map(_toHistoryEvent).toList(),
        message: json['message'] as String? ?? '',
      ));
    } on ApiException catch (e) {
      return Failure(e.message, isConnectionError: e.isConnectionError);
    }
  }

  static ClinicalHistoryEvent _toHistoryEvent(Map<String, dynamic> json) {
    final description = (json['description'] as String?)?.trim();
    return ClinicalHistoryEvent(
      id: json['id'] as String,
      type: SanitaryEventType.fromName(json['type'] as String?),
      status: SanitaryEventStatus.fromName(json['status'] as String?),
      occurredAt: DateTime.tryParse(json['occurredAt'] as String? ?? ''),
      scheduledDate: DateTime.tryParse(json['scheduledDate'] as String? ?? ''),
      description: description == null || description.isEmpty ? null : description,
    );
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
