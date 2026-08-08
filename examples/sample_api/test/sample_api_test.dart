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
    expect(body, containsPair('state', 'ready'));
    final snapshot = body['dashboard']! as Map<String, Object?>;
    expect(snapshot['summary'], containsPair('projects', 3));
    expect(snapshot['projects'], hasLength(3));
  });

  test('dashboard exposes the complete deterministic state matrix', () async {
    const expected = <String, (int, bool, bool)>{
      'ready': (200, true, false),
      'loading': (202, false, false),
      'empty': (200, false, false),
      'stale': (200, true, false),
      'unavailable': (503, false, true),
      'failure': (500, false, false),
    };

    for (final entry in expected.entries) {
      final response = await application.handler(
        Request(
          'GET',
          Uri.parse('http://localhost/v1/dashboard?state=${entry.key}'),
        ),
      );
      final body = await _body(response);

      expect(response.statusCode, entry.value.$1, reason: entry.key);
      expect(body['state'], entry.key, reason: entry.key);
      expect(body.containsKey('dashboard'), entry.value.$2, reason: entry.key);
      expect(body['recoverable'] == true, entry.value.$3, reason: entry.key);
    }

    final unavailable = await _dashboardState(application, 'unavailable');
    final failure = await _dashboardState(application, 'failure');
    expect(unavailable['error'], 'SAMPLE_DEPENDENCY_UNAVAILABLE');
    expect(unavailable['recoverable'], isTrue);
    expect(failure['error'], 'SAMPLE_API_FAILURE');
    expect(failure['recoverable'], isFalse);
    expect(failure['error'], isNot(unavailable['error']));

    final stale = await _dashboardState(application, 'stale');
    expect(stale['staleSince'], '2026-08-13T12:00:00.000Z');
  });

  test('dashboard rejects unknown matrix states', () async {
    final response = await application.handler(
      Request('GET', Uri.parse('http://localhost/v1/dashboard?state=unknown')),
    );

    expect(response.statusCode, 400);
    expect(
      await _body(response),
      containsPair('error', 'DASHBOARD_STATE_INVALID'),
    );
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

Future<Map<String, Object?>> _dashboardState(
  SampleApiHandler application,
  String state,
) async => _body(
  await application.handler(
    Request('GET', Uri.parse('http://localhost/v1/dashboard?state=$state')),
  ),
);
