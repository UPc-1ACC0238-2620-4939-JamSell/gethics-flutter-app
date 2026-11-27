import 'package:material_ui/material_ui.dart';

import '../../../core/common/result.dart';
import '../data/alert_repository.dart';
import '../domain/trend_alert.dart';

final _uuidPattern = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

/// US-21: alertas por tendencia de UN propietario. El propietario lo decide quien abre la pantalla (p. ej. un cliente
/// asignado al veterinario); sin un UUID valido no se consulta nada. Cambiar de propietario descarta el resultado del
/// anterior y las respuestas que lleguen tarde.
///
/// [allowedTypes]: tipos de tendencia que se muestran. Por defecto solo las sanitarias: las financieras y combinadas
/// pueden revelar la situacion economica del ganadero, y no hay un requisito confirmado de que el veterinario las vea.
class TrendAlertsViewModel extends ChangeNotifier {
  TrendAlertsViewModel(
    this._repository, {
    String? ownerId,
    this.allowedTypes = const {TrendType.sanitary},
  }) : _ownerId = _validOwner(ownerId);

  final AlertRepository _repository;
  final Set<TrendType> allowedTypes;

  String? _ownerId;
  bool _loading = false;
  List<TrendAlert>? _alerts;
  String _message = '';
  bool _connectionError = false;
  int _request = 0;

  static String? _validOwner(String? id) {
    final trimmed = id?.trim();
    return trimmed != null && _uuidPattern.hasMatch(trimmed) ? trimmed : null;
  }

  /// null = no hay un propietario valido: la pantalla lo avisa y no se hace ninguna consulta.
  String? get ownerId => _ownerId;
  bool get hasOwner => _ownerId != null;
  bool get loading => _loading;

  /// null = sin cargar o con error (ver [message] y [connectionError]); vacia = sin alertas que mostrar.
  List<TrendAlert>? get alerts => _alerts;
  String get message => _message;
  bool get connectionError => _connectionError;

  /// Un tipo que la app no conoce solo se muestra si se permiten todos los tipos conocidos: podria ser financiero.
  bool _isAllowed(TrendAlert alert) => alert.type == null
      ? allowedTypes.length == TrendType.values.length
      : allowedTypes.contains(alert.type);

  /// Cambia de propietario y carga sus alertas. Un id nulo o que no es UUID deja la pantalla sin propietario.
  Future<void> selectOwner(String? ownerId) {
    final owner = _validOwner(ownerId);
    if (owner == _ownerId) return Future.value();
    _ownerId = owner;
    _alerts = null;
    _message = '';
    _connectionError = false;
    _request++; // descarta la respuesta del propietario anterior
    _loading = false;
    if (owner == null) {
      notifyListeners();
      return Future.value();
    }
    return load();
  }

  /// Carga (o recarga) las alertas del propietario; con datos en pantalla los conserva hasta que llegue la respuesta.
  Future<void> load() async {
    final owner = _ownerId;
    if (owner == null) return;
    final request = ++_request;
    _loading = true;
    notifyListeners();
    final result = await _repository.getAlerts(owner);
    if (request != _request) return;
    _loading = false;
    switch (result) {
      case Success(:final data):
        // Se conserva el orden del backend (de la mas reciente a la mas antigua).
        _alerts = [
          for (final alert in data)
            if (_isAllowed(alert)) alert,
        ];
        _message = '';
        _connectionError = false;
      case Failure(:final message, :final isConnectionError):
        _alerts = null;
        _message = message;
        _connectionError = isConnectionError;
    }
    notifyListeners();
  }
}
