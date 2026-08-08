import 'dart:convert';

import 'package:sample_api/sample_api.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late SampleApiHandler application;

  setUp(() => application = SampleApiHandler());

  test('health and dashboard expose deterministic seeded state', () async {
    final health = await application.handler(
      Request('GET', Uri.parse('http://localhost/health')),
    );
    final dashboard = await application.handler(
      Request('GET', Uri.parse('http://localhost/v1/dashboard')),
    );

    expect(health.statusCode, 200);
    expect(await _body(health), containsPair('status', 'ready'));
    expect(dashboard.statusCode, 200);
    final body = await _body(dashboard);
    expect(body['summary'], containsPair('projects', 3));
    expect(body['projects'], hasLength(3));
  });

  test('task mutation changes state and reset restores the seed', () async {
    final toggle = await application.handler(
      Request(
        'POST',
        Uri.parse(
          'http://localhost/v1/projects/mobile-foundation/tasks/offline-state/toggle',
        ),
      ),
    );
    final changed = await _body(toggle);
    final project = changed['project']! as Map<String, Object?>;
    final tasks = project['tasks']! as List<Object?>;
    expect(
      tasks.cast<Map<String, Object?>>().singleWhere(
        (task) => task['id'] == 'offline-state',
      )['completed'],
      isTrue,
    );

    final reset = await application.handler(
      Request('POST', Uri.parse('http://localhost/v1/reset')),
    );
    expect(reset.statusCode, 200);
    expect(
      application.repository
          .project('mobile-foundation')!
          .tasks
          .singleWhere((task) => task.id == 'offline-state')
          .completed,
      isFalse,
    );
  });

  test('allows browser calls only from loopback origins', () async {
    final allowed = await application.handler(
      Request(
        'GET',
        Uri.parse('http://localhost/health'),
        headers: const <String, String>{'origin': 'http://127.0.0.1:8080'},
      ),
    );
    final denied = await application.handler(
      Request(
        'GET',
        Uri.parse('http://localhost/health'),
        headers: const <String, String>{'origin': 'https://example.com'},
      ),
    );

    expect(
      allowed.headers['access-control-allow-origin'],
      'http://127.0.0.1:8080',
    );
    expect(denied.statusCode, 403);
  });
}

Future<Map<String, Object?>> _body(Response response) async =>
    jsonDecode(await response.readAsString()) as Map<String, Object?>;
