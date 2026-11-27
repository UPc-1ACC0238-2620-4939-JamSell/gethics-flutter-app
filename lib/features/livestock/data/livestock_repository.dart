import '../../../core/common/result.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../domain/animal.dart';
import '../domain/farm.dart';

/// Animales y granjas: GET api/v1/animals, GET api/v1/animals/{id} y GET api/v1/farms/{id}. Solo lectura.
class LivestockRepository {
  LivestockRepository(this._api);

  final ApiClient _api;

  /// [search] busca por arete, nombre o raza (el backend ignora mayusculas); sin texto no se envia el parametro.
  Future<Result<List<Animal>>> getAnimals({String? search, AnimalStatus status = AnimalStatus.active}) async {
    final criterion = search?.trim() ?? '';
    try {
      final json = await _api.get(
        'api/v1/animals',
        query: {if (criterion.isNotEmpty) 'search': criterion, 'status': status.apiName},
      ) as Map<String, dynamic>;
      final animals = (json['animals'] as List<dynamic>? ?? const [])
          .map((item) => Animal.fromJson(item as Map<String, dynamic>))
          .toList();
      return Success(animals);
    } on ApiException catch (e) {
      return Failure(e.message, isConnectionError: e.isConnectionError);
    }
  }

  /// 404 si el animal no existe.
  Future<Result<Animal>> getAnimal(String id) async {
    try {
      final json = await _api.get('api/v1/animals/$id') as Map<String, dynamic>;
      return Success(Animal.fromJson(json));
    } on ApiException catch (e) {
      return Failure(e.message, isConnectionError: e.isConnectionError);
    }
  }

  /// 404 si la granja no existe, 400 si el id no es un UUID.
  Future<Result<Farm>> getFarm(String id) async {
    try {
      final json = await _api.get('api/v1/farms/$id') as Map<String, dynamic>;
      return Success(Farm.fromJson(json));
    } on ApiException catch (e) {
      return Failure(e.message, isConnectionError: e.isConnectionError);
    }
  }
}
