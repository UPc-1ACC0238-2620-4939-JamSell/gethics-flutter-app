import 'package:material_ui/material_ui.dart';

import '../../../core/common/result.dart';
import '../data/sanitary_repository.dart';
import '../domain/animal_option.dart';
import '../domain/clinical_history.dart';

/// US-14: historial clinico de un animal. Con [animal] preseleccionado (p. ej. desde el detalle de un animal) se
/// carga de inmediato y no se puede cambiar; sin el, [loadAnimals] trae los animales activos para elegir uno.
class ClinicalHistoryViewModel extends ChangeNotifier {
  ClinicalHistoryViewModel(this._repository, {AnimalOption? animal})
      : _animal = animal,
        lockedAnimal = animal != null;

  final SanitaryRepository _repository;

  /// true si el animal vino preseleccionado.
  final bool lockedAnimal;

  AnimalOption? _animal;
  AnimalOption? get animal => _animal;

  // --- Eleccion del animal (solo sin animal preseleccionado) ---
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

  Future<void> selectAnimal(AnimalOption? value) {
    if (lockedAnimal || value == null || value.id == _animal?.id) return Future.value();
    _animal = value;
    return load();
  }

  // --- Historial del animal ---
  bool _loading = false;
  ClinicalHistory? _history;
  String _message = '';
  bool _connectionError = false;
  int _request = 0;

  bool get loading => _loading;

  /// null = sin cargar o con error (ver [message] y [connectionError]); con lista vacia = animal sin registros.
  ClinicalHistory? get history => _history;
  String get message => _message;
  bool get connectionError => _connectionError;

  /// Carga (o recarga) el historial del animal. Una carga nueva descarta la respuesta de la anterior, y cambiar de
  /// animal descarta el historial mostrado para no confundir el de uno con el de otro.
  Future<void> load() async {
    final animal = _animal;
    if (animal == null) return;
    final request = ++_request;
    if (_history != null && _history!.animalId != animal.id) _history = null;
    _loading = true;
    notifyListeners();
    final result = await _repository.getClinicalHistory(animal.id);
    if (request != _request) return;
    _loading = false;
    switch (result) {
      case Success(:final data):
        _history = data;
        _message = '';
        _connectionError = false;
      case Failure(:final message, :final isConnectionError):
        _history = null;
        _message = message;
        _connectionError = isConnectionError;
    }
    notifyListeners();
  }
}
