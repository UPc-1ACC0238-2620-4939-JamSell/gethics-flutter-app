import 'package:flutter_test/flutter_test.dart';
import 'package:gethics/core/network/api_client.dart';
import 'package:gethics/features/livestock/data/livestock_repository.dart';
import 'package:gethics/features/livestock/domain/animal.dart';
import 'package:gethics/features/livestock/presentation/animal_list_view_model.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

String _animal(String id, String tag) => '{"id":"$id","farmId":null,"tag":"$tag","qrCode":"GTH-$id","name":null,'
    '"breed":"Holstein","sex":"FEMALE","birthDate":"2022-05-12","initialWeightKg":650.0,"photoUrl":null,"status":"ACTIVE"}';

/// Registra cada consulta (search, status) y responde con [reply].
class _Backend {
  _Backend([this.reply]);

  final http.Response Function(http.Request)? reply;
  final requests = <({String? search, String? status})>[];

  LivestockRepository get repository => LivestockRepository(
        ApiClient(
          baseUrl: 'https://api.example.com',
          client: MockClient((request) async {
            requests.add((search: request.url.queryParameters['search'], status: request.url.queryParameters['status']));
            return reply?.call(request) ??
                http.Response('{"animals":[${_animal('1', 'MX-1')}],"message":null}', 200, headers: _jsonHeaders);
          }),
        ),
      );
}

AnimalListViewModel _viewModel(_Backend backend) =>
    AnimalListViewModel(backend.repository, debounce: Duration.zero);

void main() {
  test('load trae los animales activos', () async {
    final backend = _Backend();
    final viewModel = _viewModel(backend);

    expect(viewModel.loading, isTrue);
    await viewModel.load();

    expect(viewModel.loading, isFalse);
    expect(viewModel.animals.single.tag, 'MX-1');
    expect(viewModel.error, isNull);
    expect(backend.requests, [(search: null, status: 'ACTIVE')]);
  });

  test('buscar consulta con el texto despues de la pausa y una sola vez', () async {
    final backend = _Backend();
    final viewModel = _viewModel(backend);
    await viewModel.load();

    viewModel.onQueryChanged('m');
    viewModel.onQueryChanged('mx');
    await pumpEventQueue();

    expect(backend.requests.last, (search: 'mx', status: 'ACTIVE'));
    expect(backend.requests, hasLength(2));
    expect(viewModel.hasActiveFilters, isTrue);
  });

  test('cambiar el estado consulta de inmediato con ese estado', () async {
    final backend = _Backend();
    final viewModel = _viewModel(backend);
    await viewModel.load();

    viewModel.onStatusChanged(AnimalStatus.sold);
    await pumpEventQueue();

    expect(viewModel.status, AnimalStatus.sold);
    expect(backend.requests.last, (search: null, status: 'SOLD'));
    expect(viewModel.hasActiveFilters, isTrue);
  });

  test('elegir el estado que ya esta activo no consulta de nuevo', () async {
    final backend = _Backend();
    final viewModel = _viewModel(backend);
    await viewModel.load();

    viewModel.onStatusChanged(AnimalStatus.active);
    await pumpEventQueue();

    expect(backend.requests, hasLength(1));
  });

  test('limpiar filtros restablece busqueda y estado y consulta el listado por defecto', () async {
    final backend = _Backend();
    final viewModel = _viewModel(backend);
    await viewModel.load();
    viewModel.onStatusChanged(AnimalStatus.sold);
    viewModel.onQueryChanged('mx');
    await pumpEventQueue();

    viewModel.clearFilters();
    await pumpEventQueue();

    expect(viewModel.query, '');
    expect(viewModel.status, AnimalStatus.active);
    expect(viewModel.hasActiveFilters, isFalse);
    expect(backend.requests.last, (search: null, status: 'ACTIVE'));
  });

  test('limpiar filtros sin filtros activos no consulta', () async {
    final backend = _Backend();
    final viewModel = _viewModel(backend);
    await viewModel.load();

    viewModel.clearFilters();
    await pumpEventQueue();

    expect(backend.requests, hasLength(1));
  });

  test('limpiar filtros cancela la busqueda pendiente', () async {
    final backend = _Backend();
    final viewModel = AnimalListViewModel(backend.repository, debounce: const Duration(seconds: 30));
    addTearDown(viewModel.dispose);

    viewModel.onQueryChanged('mx');
    viewModel.clearFilters();
    await pumpEventQueue();

    expect(backend.requests, [(search: null, status: 'ACTIVE')]);
  });

  test('una busqueda sin coincidencias deja la lista vacia sin error', () async {
    final backend = _Backend((_) => http.Response('{"animals":[],"message":"Sin resultados."}', 200, headers: _jsonHeaders));
    final viewModel = _viewModel(backend);

    await viewModel.load();

    expect(viewModel.animals, isEmpty);
    expect(viewModel.error, isNull);
  });

  test('un error del backend se muestra con su message y reintentar vuelve a cargar', () async {
    var fail = true;
    final backend = _Backend((_) => fail
        ? http.Response('{"message":"Estado desconocido"}', 400)
        : http.Response('{"animals":[${_animal('1', 'MX-1')}],"message":null}', 200, headers: _jsonHeaders));
    final viewModel = _viewModel(backend);

    await viewModel.load();
    expect(viewModel.error?.message, 'Estado desconocido');
    expect(viewModel.error?.isConnection, isFalse);

    fail = false;
    await viewModel.load();
    expect(viewModel.error, isNull);
    expect(viewModel.animals, hasLength(1));
  });

  test('sin conexion el error se marca como de conexion', () async {
    final viewModel = AnimalListViewModel(
      LivestockRepository(
        ApiClient(baseUrl: 'https://api.example.com', client: MockClient((_) async => throw http.ClientException('sin red'))),
      ),
      debounce: Duration.zero,
    );

    await viewModel.load();

    expect(viewModel.error?.isConnection, isTrue);
  });
}
