import 'package:material_ui/material_ui.dart';

import '../../../core/common/result.dart';
import '../../../core/common/uuid.dart';
import '../data/sanitary_repository.dart';
import '../data/sanitary_sync_service.dart';
import '../domain/animal_option.dart';
import '../domain/upcoming_event.dart';

/// US-11: error a mostrar en el formulario de registro; la pantalla lo traduce.
sealed class RegisterEventError {
  const RegisterEventError();
}

/// Falta el animal o el tipo; la pantalla marca el campo vacio.
final class MissingFieldsEventError extends RegisterEventError {
  const MissingFieldsEventError();
}

final class FutureDateEventError extends RegisterEventError {
  const FutureDateEventError();
}

/// US-13: una vacuna no se puede programar para una fecha anterior a hoy.
final class PastDateEventError extends RegisterEventError {
  const PastDateEventError();
}

final class ConnectionEventError extends RegisterEventError {
  const ConnectionEventError();
}

final class ServerEventError extends RegisterEventError {
  const ServerEventError(this.serverMessage);

  final String serverMessage;
}

/// US-11: formulario de registro de un evento sanitario ya ocurrido. [animal] preseleccionado (p. ej. desde el detalle
/// de un animal) evita cargar la lista; sin el, [loadAnimals] trae los animales activos para elegir.
class RegisterEventViewModel extends ChangeNotifier {
  RegisterEventViewModel(
    this._repository, {
    AnimalOption? animal,
    bool scheduleVaccination = false,
    DateTime Function()? now,
    String Function()? newRequestId,
  })  : _now = now ?? DateTime.now,
        _newRequestId = newRequestId ?? newUuidV4,
        _animal = animal,
        scheduling = scheduleVaccination,
        _type = scheduleVaccination ? SanitaryEventType.vaccination : null,
        lockedAnimal = animal != null {
    final current = _now();
    _date = DateTime(current.year, current.month, current.day);
  }

  final SanitaryRepository _repository;
  final DateTime Function() _now;
  final String Function() _newRequestId;

  /// US-13: el formulario programa una vacuna (tipo fijo, fecha de hoy en adelante) en lugar de registrar un evento ya
  /// ocurrido (US-11, fecha de hoy hacia atras).
  final bool scheduling;

  /// true si el animal vino preseleccionado y no se puede cambiar.
  final bool lockedAnimal;

  AnimalOption? _animal;
  SanitaryEventType? _type;
  late DateTime _date;
  bool _submitting = false;
  RegisterEventError? _error;

  // Idempotencia: el mismo clientRequestId se reutiliza al reintentar los mismos datos (un reintento tras perder la
  // respuesta no duplica el evento); si el usuario cambia algo se genera otro, porque el backend responde 409 si el
  // mismo id llega con datos distintos.
  String? _requestId;
  String? _lastPayload;

  AnimalOption? get animal => _animal;
  SanitaryEventType? get type => _type;
  DateTime get date => _date;
  bool get submitting => _submitting;
  RegisterEventError? get error => _error;

  void selectAnimal(AnimalOption? value) {
    if (lockedAnimal) return;
    _animal = value;
    _touch();
  }

  void selectType(SanitaryEventType? value) {
    _type = value;
    _touch();
  }

  void selectDate(DateTime value) {
    _date = DateTime(value.year, value.month, value.day);
    _touch();
  }

  void _touch() {
    _error = null;
    notifyListeners();
  }

  List<AnimalOption>? _animals;
  bool _loadingAnimals = false;
  String _animalsMessage = '';
  bool _animalsConnectionError = false;

  /// null = sin cargar o con error (ver [animalsMessage] y [animalsConnectionError]).
  List<AnimalOption>? get animals => _animals;
  bool get loadingAnimals => _loadingAnimals;
  String get animalsMessage => _animalsMessage;
  bool get animalsConnectionError => _animalsConnectionError;

  Future<void> loadAnimals() async {
    if (lockedAnimal || _loadingAnimals) return;
    _loadingAnimals = true;
    notifyListeners();
    final result = await _repository.getAnimals();
    _loadingAnimals = false;
    switch (result) {
      case Success(:final data):
        _animals = data;
        _animalsMessage = '';
        _animalsConnectionError = false;
      case Failure(:final message, :final isConnectionError):
        _animals = null;
        _animalsMessage = message;
        _animalsConnectionError = isConnectionError;
    }
    notifyListeners();
  }

  /// Devuelve [SanitarySaveResult.sent] si el backend registro el evento o [SanitarySaveResult.queued] si quedo guardado
  /// en el dispositivo para enviarse cuando vuelva la conexion (US-35); en ambos casos la pantalla se cierra. Con error
  /// devuelve null y deja [error]: el formulario sigue abierto con lo ingresado. Ignora un segundo toque mientras hay un
  /// envio en curso.
  Future<SanitarySaveResult?> submit(String notes) async {
    if (_submitting) return null;
    final animal = _animal;
    final type = _type;
    if (animal == null || type == null) {
      _error = const MissingFieldsEventError();
      notifyListeners();
      return null;
    }
    final current = _now();
    final today = DateTime(current.year, current.month, current.day);
    if (scheduling ? _date.isBefore(today) : _date.isAfter(today)) {
      _error = scheduling ? const PastDateEventError() : const FutureDateEventError();
      notifyListeners();
      return null;
    }
    final description = notes.trim().isEmpty ? null : notes.trim();
    final payload = '${animal.id}|${type.name}|$_date|$description';
    if (payload != _lastPayload || _requestId == null) {
      _requestId = _newRequestId();
      _lastPayload = payload;
    }
    _submitting = true;
    _error = null;
    notifyListeners();
    final result = scheduling
        ? await _repository.scheduleVaccination(
            animalId: animal.id,
            scheduledDate: _date,
            description: description,
            clientRequestId: _requestId!,
          )
        : await _repository.registerEvent(
            animalId: animal.id,
            type: type,
            occurredAt: _date,
            description: description,
            clientRequestId: _requestId!,
          );
    _submitting = false;
    switch (result) {
      case Success(:final data):
        notifyListeners();
        return data;
      case Failure(:final message, :final isConnectionError):
        _error = isConnectionError ? const ConnectionEventError() : ServerEventError(message);
        notifyListeners();
        return null;
    }
  }
}
