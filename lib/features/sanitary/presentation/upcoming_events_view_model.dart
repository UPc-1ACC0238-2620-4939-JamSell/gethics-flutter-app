import 'package:material_ui/material_ui.dart';

import '../../../core/common/result.dart';
import '../data/sanitary_repository.dart';
import '../domain/upcoming_event.dart';

/// US-46: estado de la lista de eventos proximos.
class UpcomingEventsViewModel extends ChangeNotifier {
  UpcomingEventsViewModel(this._repository);

  final SanitaryRepository _repository;

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
