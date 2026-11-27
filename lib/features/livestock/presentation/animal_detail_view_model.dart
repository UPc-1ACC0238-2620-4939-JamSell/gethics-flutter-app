import 'package:material_ui/material_ui.dart';

import '../../../core/common/result.dart';
import '../data/livestock_repository.dart';
import '../domain/animal.dart';
import '../domain/farm.dart';
import 'load_error.dart';

/// US-43: ficha completa de un animal. La granja se pide despues de mostrar el animal, para que la ficha no espere
/// por ella; si falla, solo queda sin nombre.
class AnimalDetailViewModel extends ChangeNotifier {
  AnimalDetailViewModel(this._repository, this._animalId);

  final LivestockRepository _repository;
  final String _animalId;

  Animal? _animal;
  Farm? _farm;
  bool _loading = true;
  LoadError? _error;
  bool _disposed = false;

  Animal? get animal => _animal;

  /// Granja asignada; null mientras carga, si el animal no tiene granja o si no se pudo traer.
  Farm? get farm => _farm;
  bool get loading => _loading;
  LoadError? get error => _error;

  /// Primera carga y reintento.
  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    final result = await _repository.getAnimal(_animalId);
    if (_disposed) return;
    _loading = false;
    switch (result) {
      case Success(:final data):
        _animal = data;
      case Failure(:final message, :final isConnectionError):
        _error = LoadError(message, isConnection: isConnectionError);
    }
    notifyListeners();
    final farmId = _animal?.farmId;
    if (_error != null) return;
    if (farmId == null) {
      _farm = null;
      return;
    }
    await _loadFarm(farmId);
  }

  Future<void> _loadFarm(String farmId) async {
    if (_farm?.id == farmId) return;
    final result = await _repository.getFarm(farmId);
    if (_disposed) return;
    if (result case Success(:final data)) {
      _farm = data;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
