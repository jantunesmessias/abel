import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sample_flutter/showcase_api.dart';
import 'package:sample_flutter/showcase_models.dart';

void main() {
  test(
    'HTTP client requests and decodes every typed dashboard state',
    () async {
      for (final state in ShowcaseDashboardState.values) {
        final response = _responseFor(state);
        final client = MockClient((request) async {
          expect(request.url.path, '/v1/dashboard');
          expect(request.url.queryParameters['state'], state.name);
          return http.Response(
            jsonEncode(response.body),
            response.status,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        });
        final api = HttpShowcaseApi(
          baseUrl: 'http://127.0.0.1:8181',
          dashboardState: state,
          client: client,
        );

        final result = await api.loadDashboard();

        expect(result.state, state);
        expect(
          result.dashboard != null,
          state == ShowcaseDashboardState.ready ||
              state == ShowcaseDashboardState.stale,
        );
      }
    },
  );

  test('unavailable and failure retain distinct typed diagnostics', () {
    final unavailable = ShowcaseDashboardResult.fromJson(
      _responseFor(ShowcaseDashboardState.unavailable).body,
    );
    final failure = ShowcaseDashboardResult.fromJson(
      _responseFor(ShowcaseDashboardState.failure).body,
    );

    expect(unavailable.state, ShowcaseDashboardState.unavailable);
    expect(unavailable.recoverable, isTrue);
    expect(unavailable.errorCode, 'SAMPLE_DEPENDENCY_UNAVAILABLE');
    expect(failure.state, ShowcaseDashboardState.failure);
    expect(failure.recoverable, isFalse);
    expect(failure.errorCode, 'SAMPLE_API_FAILURE');
  });

  test('HTTP status must agree with the typed state', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode(_responseFor(ShowcaseDashboardState.unavailable).body),
        500,
      ),
    );
    final api = HttpShowcaseApi(
      baseUrl: 'http://127.0.0.1:8181',
      dashboardState: ShowcaseDashboardState.unavailable,
      client: client,
    );

    await expectLater(api.loadDashboard(), throwsA(isA<FormatException>()));
  });
}

({int status, Map<String, Object?> body}) _responseFor(
  ShowcaseDashboardState state,
) => switch (state) {
  ShowcaseDashboardState.ready => (status: 200, body: _data('ready')),
  ShowcaseDashboardState.loading => (
    status: 202,
    body: <String, Object?>{'state': 'loading', 'retryAfterMs': 1000},
  ),
  ShowcaseDashboardState.empty => (
    status: 200,
    body: <String, Object?>{'state': 'empty'},
  ),
  ShowcaseDashboardState.stale => (
    status: 200,
    body: <String, Object?>{
      ..._data('stale'),
      'staleSince': '2026-08-13T12:00:00.000Z',
    },
  ),
  ShowcaseDashboardState.unavailable => (
    status: 503,
    body: <String, Object?>{
      'state': 'unavailable',
      'error': 'SAMPLE_DEPENDENCY_UNAVAILABLE',
      'recoverable': true,
    },
  ),
  ShowcaseDashboardState.failure => (
    status: 500,
    body: <String, Object?>{
      'state': 'failure',
      'error': 'SAMPLE_API_FAILURE',
      'recoverable': false,
    },
  ),
};

Map<String, Object?> _data(String state) => <String, Object?>{
  'state': state,
  'dashboard': <String, Object?>{
    'revision': 1,
    'summary': <String, Object?>{
      'projects': 0,
      'completedTasks': 0,
      'totalTasks': 0,
      'atRiskProjects': 0,
    },
    'projects': <Object?>[],
    'activity': <Object?>[],
  },
};
