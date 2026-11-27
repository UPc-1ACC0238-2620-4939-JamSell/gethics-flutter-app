import 'package:material_ui/material_ui.dart';

import '../../../core/common/result.dart';
import '../data/sanitary_repository.dart';
import '../domain/upcoming_event.dart';

/// US-12: calendario sanitario por mes. Empieza en el mes actual y navega al anterior y al siguiente (Dic <-> Ene
/// cambia de anio). Es independiente de las alertas de US-46 (ventana de dias desde hoy): cambiar de mes no las toca.
class SanitaryCalendarViewModel extends ChangeNotifier {
  SanitaryCalendarViewModel(
    this._repository, {
    DateTime Function()? now,
    this._debounce = const Duration(milliseconds: 300),
  }) : _now = now ?? DateTime.now {
    final current = _now();
    _month = DateTime(current.year, current.month);
  }

  final SanitaryRepository _repository;
  final DateTime Function() _now;
  final Duration _debounce;

  late DateTime _month;
  bool _loading = false;
  List<UpcomingEvent>? _events;
  String _message = '';
  bool _connectionError = false;
  int _request = 0;

  // Nombres de los animales: se piden una vez y se reutilizan al cambiar de mes; load() (reintento, actualizar,
  // reprogramacion) los vuelve a pedir.
  Map<String, String>? _names;

  /// Primer dia del mes mostrado.
  DateTime get month => _month;
  bool get loading => _loading;

  /// null = cargando o con error (ver [message] y [connectionError]); vacia = mes sin actividades.
  List<UpcomingEvent>? get events => _events;
  String get message => _message;
  bool get connectionError => _connectionError;

  Future<void> previousMonth() => _goTo(DateTime(_month.year, _month.month - 1));

  Future<void> nextMonth() => _goTo(DateTime(_month.year, _month.month + 1));

  /// Cambia el mes al instante (sin datos del anterior) y pide el nuevo despues de [_debounce]: si el usuario sigue
  /// tocando, solo se consulta el ultimo mes. Una respuesta que llega tarde de un mes anterior se descarta.
  Future<void> _goTo(DateTime month) async {
    _month = month;
    final request = ++_request;
    _events = null;
    _message = '';
    _connectionError = false;
    _loading = true;
    notifyListeners();
    await Future<void>.delayed(_debounce);
    if (request != _request) return;
    await _fetch(request);
  }

  /// Carga (o recarga) el mes mostrado; con datos ya en pantalla los conserva hasta que llegue la respuesta.
  Future<void> load() {
    _names = null;
    return _fetch(++_request);
  }

  Future<void> _fetch(int request) async {
    final month = _month;
    _loading = true;
    notifyListeners();
    final names = _names ?? await _repository.getAnimalNames();
    if (request != _request) return;
    if (names.isNotEmpty) _names = names;
    final result = await _repository.getCalendar(year: month.year, month: month.month, today: _now(), names: names);
    if (request != _request) return;
    _loading = false;
    switch (result) {
      case Success(:final data):
        _events = data;
        _message = '';
        _connectionError = false;
      case Failure(:final message, :final isConnectionError):
        _events = null;
        _message = message;
        _connectionError = isConnectionError;
    }
    notifyListeners();
  }
}
