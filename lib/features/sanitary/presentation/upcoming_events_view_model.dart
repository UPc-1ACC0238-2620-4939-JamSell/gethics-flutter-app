import 'package:material_ui/material_ui.dart';

import '../../../core/common/result.dart';
import '../data/sanitary_repository.dart';
import '../domain/upcoming_event.dart';

/// US-47: error a mostrar dentro del dialogo de reprogramacion; la pantalla lo traduce.
sealed class RescheduleError {
  const RescheduleError();
}

final class PastDateRescheduleError extends RescheduleError {
  const PastDateRescheduleError();
}

final class ConnectionRescheduleError extends RescheduleError {
  const ConnectionRescheduleError();
}

final class ServerRescheduleError extends RescheduleError {
  const ServerRescheduleError(this.serverMessage);

  final String serverMessage;
}

/// US-33: error a mostrar en el dialogo de cancelacion; la pantalla lo traduce.
sealed class ActionError {
  const ActionError();
}

final class ConnectionActionError extends ActionError {
  const ConnectionActionError();
}

final class ServerActionError extends ActionError {
  const ServerActionError(this.serverMessage);

  final String serverMessage;
}

/// US-13: la fecha de aplicacion no puede ser posterior a hoy.
final class FutureDateActionError extends ActionError {
  const FutureDateActionError();
}

/// US-46: estado de la lista de eventos proximos. US-47: reprogramacion y US-33: cancelacion de un evento de la lista
/// (las tarjetas del calendario mensual usan este mismo ViewModel, asi que comparten el estado de "ocupado").
class UpcomingEventsViewModel extends ChangeNotifier {
  UpcomingEventsViewModel(this._repository, {DateTime Function()? now, this.onEventsChanged}) : _now = now ?? DateTime.now;

  final SanitaryRepository _repository;
  final DateTime Function() _now;

  /// US-12: se llama tras reprogramar o cancelar con exito, para que el calendario mensual (que muestra los mismos
  /// eventos) se recargue: el evento sale del mes original (y aparece en el nuevo si se reprogramo).
  final void Function()? onEventsChanged;

  bool _rescheduling = false;
  RescheduleError? _rescheduleError;

  bool _cancelling = false;
  bool _completing = false;
  ActionError? _actionError;

  bool get rescheduling => _rescheduling;
  bool get cancelling => _cancelling;
  bool get completing => _completing;
  ActionError? get actionError => _actionError;

  /// Hay una reprogramacion, cancelacion o aplicacion en curso: las acciones sobre eventos se deshabilitan hasta que termine.
  bool get busy => _rescheduling || _cancelling || _completing;

  void clearActionError() {
    if (_actionError == null) return;
    _actionError = null;
    notifyListeners();
  }

  /// US-13: registra como aplicada (SCHEDULED -> COMPLETED) una vacuna programada. Es el mismo evento: el backend
  /// conserva su fecha programada, fija la de aplicacion y deja de generar o reintentar su recordatorio. Devuelve true
  /// si lo acepto (el dialogo se cierra y las listas se recargan: el evento ya no esta pendiente). No admite una fecha
  /// de aplicacion posterior a hoy. Ignora la solicitud si hay otra accion en curso.
  Future<bool> completeEvent(UpcomingEvent event, DateTime appliedOn) async {
    if (busy) return false;
    final now = _now();
    if (DateTime(appliedOn.year, appliedOn.month, appliedOn.day).isAfter(DateTime(now.year, now.month, now.day))) {
      _actionError = const FutureDateActionError();
      notifyListeners();
      return false;
    }
    _completing = true;
    _actionError = null;
    notifyListeners();
    final result = await _repository.completeEvent(animalId: event.animalId, eventId: event.id, occurredAt: appliedOn);
    _completing = false;
    switch (result) {
      case Success():
        notifyListeners();
        onEventsChanged?.call();
        await load();
        return true;
      case Failure(:final message, :final isConnectionError):
        _actionError = isConnectionError ? const ConnectionActionError() : ServerActionError(message);
        notifyListeners();
        return false;
    }
  }

  /// US-33: devuelve true si el backend cancelo el evento (el dialogo se cierra y las listas se recargan). Con error
  /// devuelve false y deja [actionError]: el evento sigue en las listas, que solo cambian tras una respuesta exitosa.
  /// Ignora una segunda solicitud mientras otra reprogramacion o cancelacion esta en curso.
  Future<bool> cancelEvent(UpcomingEvent event) async {
    if (busy) return false;
    _cancelling = true;
    _actionError = null;
    notifyListeners();
    final result = await _repository.cancelEvent(animalId: event.animalId, eventId: event.id);
    _cancelling = false;
    switch (result) {
      case Success():
        notifyListeners();
        onEventsChanged?.call();
        await load();
        return true;
      case Failure(:final message, :final isConnectionError):
        _actionError = isConnectionError ? const ConnectionActionError() : ServerActionError(message);
        notifyListeners();
        return false;
    }
  }
  RescheduleError? get rescheduleError => _rescheduleError;

  void clearRescheduleError() {
    if (_rescheduleError == null) return;
    _rescheduleError = null;
    notifyListeners();
  }

  /// Devuelve true si el backend acepto la nueva fecha (el dialogo se cierra y la lista se recarga). Con error devuelve
  /// false y deja [rescheduleError]: el dialogo sigue abierto con lo ingresado. Ignora un segundo toque en curso.
  Future<bool> reschedule(UpcomingEvent event, DateTime newDate, String notes) async {
    if (busy) return false;
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    if (DateTime(newDate.year, newDate.month, newDate.day).isBefore(today)) {
      _rescheduleError = const PastDateRescheduleError();
      notifyListeners();
      return false;
    }
    _rescheduling = true;
    _rescheduleError = null;
    notifyListeners();
    final trimmed = notes.trim();
    final result = await _repository.rescheduleEvent(
      animalId: event.animalId,
      eventId: event.id,
      scheduledDate: newDate,
      description: trimmed.isEmpty ? null : trimmed,
    );
    _rescheduling = false;
    switch (result) {
      case Success():
        notifyListeners();
        onEventsChanged?.call();
        await load();
        return true;
      case Failure(:final message, :final isConnectionError):
        _rescheduleError = isConnectionError ? const ConnectionRescheduleError() : ServerRescheduleError(message);
        notifyListeners();
        return false;
    }
  }

  bool _loading = false;
  List<UpcomingEvent>? _events;
  String _message = '';
  bool _connectionError = false;
  int _request = 0;

  bool get loading => _loading;

  /// null = error (ver [message] y [connectionError]); vacia = sin alertas ([message] del backend o '' para el texto local).
  List<UpcomingEvent>? get events => _events;
  String get message => _message;
  bool get connectionError => _connectionError;

  /// Cantidad de eventos vencidos o urgentes, para el aviso de atencion.
  int get needAttention => _events?.where((e) => e.urgency != EventUrgency.upcoming).length ?? 0;

  Future<void> load() async {
    final request = ++_request; // una carga nueva descarta la respuesta de la anterior
    _loading = true;
    notifyListeners();
    final result = await _repository.getUpcomingEvents();
    if (request != _request) return;
    _loading = false;
    switch (result) {
      case Success(:final data):
        _events = data.events;
        _message = data.message;
        _connectionError = false;
      case Failure(:final message, :final isConnectionError):
        _events = null;
        _message = message;
        _connectionError = isConnectionError;
    }
    notifyListeners();
  }
}
