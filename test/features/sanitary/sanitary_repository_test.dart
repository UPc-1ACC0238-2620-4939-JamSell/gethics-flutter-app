import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gethics/core/common/result.dart';
import 'package:gethics/core/network/api_client.dart';
import 'package:gethics/features/sanitary/data/sanitary_repository.dart';
import 'package:gethics/features/sanitary/domain/upcoming_event.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const upcomingJson = '''
{"today":"2026-11-26","days":7,"message":null,"events":[
 {"id":"e1","animalId":"a1","type":"VACCINATION","scheduledDate":"2026-11-24","description":"Aftosa","daysUntil":-2,"overdue":true},
 {"id":"e2","animalId":"a2","type":"CHECKUP","scheduledDate":"2026-11-27","description":" ","daysUntil":1,"overdue":false},
 {"id":"e3","animalId":"a3","type":"NUEVO","scheduledDate":"2026-12-01","description":null,"daysUntil":5,"overdue":false}]}''';

const animalsJson = '''
{"animals":[{"id":"a1","name":"Lola","tag":"TAG-1"},{"id":"a2","name":null,"tag":"TAG-2"}],"message":null}''';

SanitaryRepository repository(Future<http.Response> Function(http.Request) handler) =>
    SanitaryRepository(ApiClient(baseUrl: 'https://api.example.com', client: MockClient(handler)));

void main() {
  test('pide la ventana de 7 dias y resuelve nombre o arete del animal', () async {
    final paths = <String>[];
    final repo = repository((request) async {
      paths.add(request.url.toString());
      return http.Response(request.url.path.endsWith('upcoming') ? upcomingJson : animalsJson, 200);
    });

    final result = await repo.getUpcomingEvents();

    expect(paths, [
      'https://api.example.com/api/v1/sanitary-events/upcoming?days=7',
      'https://api.example.com/api/v1/animals?status=ACTIVE',
    ]);
    final events = (result as Success<UpcomingEvents>).data.events;
    expect(events.map((e) => e.animalLabel), ['Lola', 'TAG-2', null]);
    expect(events.map((e) => e.urgency), [EventUrgency.overdue, EventUrgency.urgent, EventUrgency.upcoming]);
    expect(events[0].scheduledDate, DateTime(2026, 11, 24));
    expect(events[1].description, isNull);
    expect(events[2].type, SanitaryEventType.other);
  });

  test('sin eventos devuelve el mensaje del backend y no pide los animales', () async {
    var calls = 0;
    final repo = repository((_) async {
      calls++;
      return http.Response('{"today":"2026-11-26","days":7,"events":[],"message":"No hay alertas pendientes."}', 200);
    });

    final data = (await repo.getUpcomingEvents() as Success<UpcomingEvents>).data;

    expect(data.events, isEmpty);
    expect(data.message, 'No hay alertas pendientes.');
    expect(calls, 1);
  });

  test('si fallan los animales los eventos se devuelven sin nombre', () async {
    final repo = repository((request) async => request.url.path.endsWith('upcoming')
        ? http.Response(upcomingJson, 200)
        : http.Response('{"message":"error"}', 500));

    final events = (await repo.getUpcomingEvents() as Success<UpcomingEvents>).data.events;

    expect(events.every((e) => e.animalLabel == null), isTrue);
  });

  test('error del backend y sin conexion se devuelven como Failure', () async {
    final error = await repository((_) async => http.Response('{"message":"Ventana invalida"}', 400)).getUpcomingEvents();
    final offline = await repository((_) async => throw const SocketException('sin red')).getUpcomingEvents();

    expect(error, isA<Failure<UpcomingEvents>>().having((f) => f.message, 'message', 'Ventana invalida'));
    expect(offline, isA<Failure<UpcomingEvents>>().having((f) => f.isConnectionError, 'isConnectionError', true));
  });

  test('urgencia segun los dias restantes', () {
    expect(urgencyOf(-1, overdue: true), EventUrgency.overdue);
    expect(urgencyOf(-3, overdue: false), EventUrgency.overdue);
    expect(urgencyOf(0, overdue: false), EventUrgency.urgent);
    expect(urgencyOf(urgentWithinDays, overdue: false), EventUrgency.urgent);
    expect(urgencyOf(urgentWithinDays + 1, overdue: false), EventUrgency.upcoming);
  });
}
