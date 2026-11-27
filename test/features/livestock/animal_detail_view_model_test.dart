import 'package:flutter_test/flutter_test.dart';
import 'package:gethics/core/network/api_client.dart';
import 'package:gethics/features/livestock/data/livestock_repository.dart';
import 'package:gethics/features/livestock/presentation/animal_detail_view_model.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _jsonHeaders = {'content-type': 'application/json; charset=utf-8'};
const _farmJson = '{"id":"f1","ownerId":"o1","name":"Fundo Sur","location":"Jauja","sizeHectares":12.5,"status":"ACTIVE"}';

String _animalJson(String? farmId) => '{"id":"a1","farmId":${farmId == null ? 'null' : '"$farmId"'},"tag":"MX-1",'
    '"qrCode":"GTH-1","name":null,"breed":"Holstein","sex":"FEMALE","birthDate":"2022-05-12",'
    '"initialWeightKg":650.0,"photoUrl":null,"status":"ACTIVE"}';

/// Responde segun la ruta y registra las rutas pedidas.
class _Backend {
  _Backend({required this.animal, required this.farm});

  final http.Response Function() animal;
  final http.Response Function() farm;
  final paths = <String>[];

  AnimalDetailViewModel viewModel() => AnimalDetailViewModel(
        LivestockRepository(
          ApiClient(
            baseUrl: 'https://api.example.com',
            client: MockClient((request) async {
              paths.add(request.url.path);
              return request.url.path.startsWith('/api/v1/farms') ? farm() : animal();
            }),
          ),
        ),
        'a1',
      );
}

http.Response _ok(String body) => http.Response(body, 200, headers: _jsonHeaders);

void main() {
  test('load trae el animal y su granja asignada', () async {
    final backend = _Backend(animal: () => _ok(_animalJson('f1')), farm: () => _ok(_farmJson));
    final viewModel = backend.viewModel();

    expect(viewModel.loading, isTrue);
    await viewModel.load();

    expect(viewModel.loading, isFalse);
    expect(viewModel.error, isNull);
    expect(viewModel.animal?.tag, 'MX-1');
    expect(viewModel.farm?.name, 'Fundo Sur');
    expect(backend.paths, ['/api/v1/animals/a1', '/api/v1/farms/f1']);
  });

  test('un animal sin granja no consulta granjas', () async {
    final backend = _Backend(animal: () => _ok(_animalJson(null)), farm: () => _ok(_farmJson));
    final viewModel = backend.viewModel();

    await viewModel.load();

    expect(viewModel.animal, isNotNull);
    expect(viewModel.farm, isNull);
    expect(backend.paths, ['/api/v1/animals/a1']);
  });

  test('si la granja falla, el animal igual se muestra', () async {
    final backend = _Backend(
      animal: () => _ok(_animalJson('f1')),
      farm: () => http.Response('{"message":"La granja no existe."}', 404),
    );
    final viewModel = backend.viewModel();

    await viewModel.load();

    expect(viewModel.animal, isNotNull);
    expect(viewModel.error, isNull);
    expect(viewModel.farm, isNull);
  });

  test('un animal inexistente muestra el message del backend', () async {
    final backend = _Backend(
      animal: () => http.Response('{"message":"El animal no existe."}', 404),
      farm: () => _ok(_farmJson),
    );
    final viewModel = backend.viewModel();

    await viewModel.load();

    expect(viewModel.animal, isNull);
    expect(viewModel.error?.message, 'El animal no existe.');
    expect(viewModel.error?.isConnection, isFalse);
    expect(backend.paths, ['/api/v1/animals/a1']);
  });

  test('sin conexion marca el error como de conexion y reintentar carga el animal', () async {
    var offline = true;
    final viewModel = AnimalDetailViewModel(
      LivestockRepository(
        ApiClient(
          baseUrl: 'https://api.example.com',
          client: MockClient((request) async {
            if (offline) throw http.ClientException('sin red');
            return request.url.path.startsWith('/api/v1/farms') ? _ok(_farmJson) : _ok(_animalJson('f1'));
          }),
        ),
      ),
      'a1',
    );

    await viewModel.load();
    expect(viewModel.error?.isConnection, isTrue);

    offline = false;
    await viewModel.load();
    expect(viewModel.error, isNull);
    expect(viewModel.animal?.tag, 'MX-1');
    expect(viewModel.farm?.name, 'Fundo Sur');
  });

  test('recargar con la misma granja no la vuelve a pedir', () async {
    final backend = _Backend(animal: () => _ok(_animalJson('f1')), farm: () => _ok(_farmJson));
    final viewModel = backend.viewModel();

    await viewModel.load();
    await viewModel.load();

    expect(backend.paths.where((path) => path.startsWith('/api/v1/farms')), hasLength(1));
  });
}
