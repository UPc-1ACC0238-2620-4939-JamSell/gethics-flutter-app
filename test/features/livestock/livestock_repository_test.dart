import 'package:flutter_test/flutter_test.dart';
import 'package:gethics/core/common/result.dart';
import 'package:gethics/core/network/api_client.dart';
import 'package:gethics/features/livestock/data/livestock_repository.dart';
import 'package:gethics/features/livestock/domain/animal.dart';
import 'package:gethics/features/livestock/domain/farm.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _animalJson = '{"id":"a1","farmId":"f1","tag":"MX-1","qrCode":"GTH-1","name":null,"breed":"Holstein",'
    '"sex":"FEMALE","birthDate":"2022-05-12","initialWeightKg":650.0,"photoUrl":null,"status":"ACTIVE"}';
const _farmJson = '{"id":"f1","ownerId":"o1","name":"Fundo Sur","location":"Jauja, Junin","sizeHectares":12.5,"status":"ACTIVE"}';
const _jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

LivestockRepository _repository(Future<http.Response> Function(http.Request) handler) =>
    LivestockRepository(ApiClient(baseUrl: 'https://api.example.com', client: MockClient(handler)));

void main() {
  group('getAnimals', () {
    test('envia el estado y el texto de busqueda y devuelve los animales', () async {
      late http.Request sent;
      final repository = _repository((request) async {
        sent = request;
        return http.Response('{"animals":[$_animalJson],"message":null}', 200, headers: _jsonHeaders);
      });

      final result = await repository.getAnimals(search: ' mx ', status: AnimalStatus.sold);

      expect(sent.url.path, '/api/v1/animals');
      expect(sent.url.queryParameters, {'search': 'mx', 'status': 'SOLD'});
      final animals = (result as Success<List<Animal>>).data;
      expect(animals, hasLength(1));
      expect(animals.first.tag, 'MX-1');
      expect(animals.first.status, AnimalStatus.active);
    });

    test('sin texto de busqueda no envia el parametro search y usa Activos por defecto', () async {
      late http.Request sent;
      final repository = _repository((request) async {
        sent = request;
        return http.Response('{"animals":[],"message":"No hay animales registrados."}', 200, headers: _jsonHeaders);
      });

      final result = await repository.getAnimals(search: '   ');

      expect(sent.url.queryParameters, {'status': 'ACTIVE'});
      expect((result as Success<List<Animal>>).data, isEmpty);
    });

    test('un error del backend devuelve su message', () async {
      final repository = _repository((_) async => http.Response('{"message":"Estado desconocido"}', 400));

      final result = await repository.getAnimals();

      expect(result, isA<Failure<List<Animal>>>().having((f) => f.message, 'message', 'Estado desconocido'));
    });

    test('sin conexion devuelve un error de conexion', () async {
      final repository = _repository((_) async => throw http.ClientException('sin red'));

      final result = await repository.getAnimals();

      expect(result, isA<Failure<List<Animal>>>().having((f) => f.isConnectionError, 'isConnectionError', isTrue));
    });
  });

  group('getAnimal', () {
    test('lee todos los datos de la ficha', () async {
      late http.Request sent;
      final repository = _repository((request) async {
        sent = request;
        return http.Response(_animalJson, 200, headers: _jsonHeaders);
      });

      final animal = ((await repository.getAnimal('a1')) as Success<Animal>).data;

      expect(sent.url.path, '/api/v1/animals/a1');
      expect(animal.id, 'a1');
      expect(animal.farmId, 'f1');
      expect(animal.qrCode, 'GTH-1');
      expect(animal.name, isNull);
      expect(animal.breed, 'Holstein');
      expect(animal.sex, 'FEMALE');
      expect(animal.birthDate, DateTime(2022, 5, 12));
      expect(animal.weightKg, 650.0);
    });

    test('los datos que faltan quedan en null y un estado desconocido no se inventa', () async {
      const json = '{"id":"a2","farmId":null,"tag":"MX-2","qrCode":null,"name":null,"breed":"Angus","sex":null,'
          '"birthDate":null,"initialWeightKg":null,"photoUrl":null,"status":"OTRO"}';
      final repository = _repository((_) async => http.Response(json, 200, headers: _jsonHeaders));

      final animal = ((await repository.getAnimal('a2')) as Success<Animal>).data;

      expect(animal.farmId, isNull);
      expect(animal.birthDate, isNull);
      expect(animal.weightKg, isNull);
      expect(animal.status, isNull);
    });

    test('un animal inexistente devuelve el message del backend', () async {
      final repository = _repository((_) async => http.Response('{"message":"El animal no existe."}', 404));

      final result = await repository.getAnimal('x');

      expect(result, isA<Failure<Animal>>().having((f) => f.message, 'message', 'El animal no existe.'));
    });
  });

  group('getFarm', () {
    test('lee la granja por id', () async {
      late http.Request sent;
      final repository = _repository((request) async {
        sent = request;
        return http.Response(_farmJson, 200, headers: _jsonHeaders);
      });

      final farm = ((await repository.getFarm('f1')) as Success<Farm>).data;

      expect(sent.url.path, '/api/v1/farms/f1');
      expect(farm.name, 'Fundo Sur');
      expect(farm.location, 'Jauja, Junin');
    });

    test('una granja inexistente devuelve el message del backend', () async {
      final repository = _repository((_) async => http.Response('{"message":"La granja no existe."}', 404));

      final result = await repository.getFarm('f9');

      expect(result, isA<Failure<Farm>>().having((f) => f.message, 'message', 'La granja no existe.'));
    });
  });

  group('AnimalStatus.fromApi', () {
    test('reconoce los cuatro estados y devuelve null si no se conoce', () {
      expect(AnimalStatus.fromApi('SOLD'), AnimalStatus.sold);
      expect(AnimalStatus.fromApi('DECEASED'), AnimalStatus.deceased);
      expect(AnimalStatus.fromApi('INACTIVE'), AnimalStatus.inactive);
      expect(AnimalStatus.fromApi(null), isNull);
      expect(AnimalStatus.fromApi('active'), isNull);
    });
  });
}
