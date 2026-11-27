import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../core/common/result.dart';
import '../data/livestock_repository.dart';
import '../domain/animal.dart';
import 'load_error.dart';

/// US-42: listado de animales con busqueda por texto (arete, nombre o raza), filtro por estado y limpieza de filtros.
/// La busqueda espera [debounce] sin teclear antes de consultar; el cambio de estado consulta de inmediato. Una
/// respuesta que llega tarde (de una busqueda anterior) se descarta.
class AnimalListViewModel extends ChangeNotifier {
  AnimalListViewModel(this._repository, {this.debounce = const Duration(milliseconds: 300)});

  final LivestockRepository _repository;

  /// Pausa sin teclear antes de consultar la busqueda.
  final Duration debounce;

  String _query = '';
  AnimalStatus _status = AnimalStatus.active;
  List<Animal> _animals = const [];
  bool _loading = true;
  LoadError? _error;
  Timer? _timer;
  int _requestId = 0;
  bool _disposed = false;

  String get query => _query;
  AnimalStatus get status => _status;
  List<Animal> get animals => _animals;
  bool get loading => _loading;
  LoadError? get error => _error;

  /// true cuando hay texto de busqueda o un estado distinto al de por defecto (Activos).
  bool get hasActiveFilters => _query.trim().isNotEmpty || _status != AnimalStatus.active;

  /// Primera carga y reintento.
  Future<void> load() => _fetch();

  void onQueryChanged(String value) {
    _query = value;
    _timer?.cancel();
    _timer = Timer(debounce, _fetch);
    notifyListeners();
  }

  void onStatusChanged(AnimalStatus status) {
    if (status == _status) return;
    _status = status;
    _timer?.cancel();
    _fetch();
  }

  /// Restablece busqueda y estado y vuelve a pedir el listado por defecto. Sin filtros activos no hace nada.
  void clearFilters() {
    if (!hasActiveFilters) return;
    _query = '';
    _status = AnimalStatus.active;
    _timer?.cancel();
    _fetch();
  }

  Future<void> _fetch() async {
    final requestId = ++_requestId;
    _loading = true;
    _error = null;
    notifyListeners();
    final result = await _repository.getAnimals(search: _query, status: _status);
    if (_disposed || requestId != _requestId) return;
    _loading = false;
    switch (result) {
      case Success(:final data):
        _animals = data;
      case Failure(:final message, :final isConnectionError):
        _error = LoadError(message, isConnection: isConnectionError);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
