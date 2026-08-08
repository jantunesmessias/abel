import 'dart:convert';

import 'package:sample_api/src/showcase_repository.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

final class SampleApiHandler {
  SampleApiHandler({ShowcaseRepository? repository})
    : repository = repository ?? ShowcaseRepository();

  final ShowcaseRepository repository;

  Handler get handler => const Pipeline()
      .addMiddleware(_errorMiddleware())
      .addMiddleware(_corsMiddleware())
      .addMiddleware(logRequests())
      .addHandler(_router.call);

  late final Router _router = Router()
    ..get('/health', _health)
    ..get('/v1/dashboard', _dashboard)
    ..get('/v1/projects', _projects)
    ..get('/v1/projects/<projectId>', _project)
    ..post('/v1/projects/<projectId>/tasks/<taskId>/toggle', _toggleTask)
    ..post('/v1/reset', _reset)
    ..get('/v1/runtime/configuration', _runtimeConfiguration)
    ..get('/v1/unavailable', _unavailable)
    ..get('/v1/failure', _failure)
    ..options('/<ignored|.*>', _options);

  Response _health(Request request) => _json(<String, Object?>{
    'status': 'ready',
    'service': 'sample-api',
    'version': '1',
    'revision': repository.revision,
  });

  Response _dashboard(Request request) {
    final requestedState = request.url.queryParameters['state'];
    final state = _dashboardState(requestedState);
    if (state == null) {
      return _json(const <String, Object?>{
        'error': 'DASHBOARD_STATE_INVALID',
      }, status: 400);
    }
    return switch (state) {
      DashboardState.ready => _dashboardData(state),
      DashboardState.loading => _json(const <String, Object?>{
        'state': 'loading',
        'retryAfterMs': 1000,
      }, status: 202),
      DashboardState.empty => _json(const <String, Object?>{'state': 'empty'}),
      DashboardState.stale => _json(<String, Object?>{
        'state': state.name,
        'staleSince': '2026-08-13T12:00:00.000Z',
        'dashboard': repository.dashboard(),
      }),
      DashboardState.unavailable => _unavailable(request),
      DashboardState.failure => _failure(request),
    };
  }

  Response _dashboardData(DashboardState state) => _json(<String, Object?>{
    'state': state.name,
    'dashboard': repository.dashboard(),
  });

  Response _projects(Request request) => _json(<String, Object?>{
    'revision': repository.revision,
    'items': <Object?>[
      for (final project in repository.projects) project.toJson(),
    ],
  });

  Response _project(Request request, String projectId) {
    final project = repository.project(projectId);
    return project == null
        ? _notFound('PROJECT_NOT_FOUND')
        : _json(project.toJson());
  }

  Response _toggleTask(Request request, String projectId, String taskId) {
    final project = repository.toggleTask(projectId, taskId);
    return project == null
        ? _notFound('PROJECT_OR_TASK_NOT_FOUND')
        : _json(<String, Object?>{
            'revision': repository.revision,
            'project': project.toJson(),
          });
  }

  Response _reset(Request request) {
    repository.reset();
    return _json(<String, Object?>{
      'status': 'reset',
      'revision': repository.revision,
    });
  }

  Response _runtimeConfiguration(Request request) => _json(<String, Object?>{
    'api': 'sample-api',
    'view': request.url.queryParameters['view'] ?? 'default',
    'mode': 'upstream',
    'synthetic': false,
    'revision': repository.revision,
  });

  Response _unavailable(Request request) => _json(const <String, Object?>{
    'state': 'unavailable',
    'error': 'SAMPLE_DEPENDENCY_UNAVAILABLE',
    'recoverable': true,
  }, status: 503);

  Response _failure(Request request) => _json(const <String, Object?>{
    'state': 'failure',
    'error': 'SAMPLE_API_FAILURE',
    'recoverable': false,
  }, status: 500);

  Response _options(Request request, String ignored) => Response(204);

  Response _notFound(String code) =>
      _json(<String, Object?>{'error': code}, status: 404);
}

DashboardState? _dashboardState(String? value) {
  if (value == null) return DashboardState.ready;
  for (final state in DashboardState.values) {
    if (state.name == value) return state;
  }
  return null;
}

Middleware _errorMiddleware() =>
    (inner) => (request) async {
      try {
        return await inner(request);
      } on FormatException catch (error) {
        return _json(<String, Object?>{
          'error': 'INVALID_REQUEST',
          'message': error.message,
        }, status: 400);
      } on Object {
        return _json(const <String, Object?>{
          'error': 'SAMPLE_API_INTERNAL',
        }, status: 500);
      }
    };

Middleware _corsMiddleware() =>
    (inner) => (request) async {
      final origin = request.headers['origin'];
      if (origin != null && !_isLoopbackOrigin(origin)) {
        return _json(const <String, Object?>{
          'error': 'ORIGIN_NOT_ALLOWED',
        }, status: 403);
      }
      final response = await inner(request);
      return response.change(
        headers: <String, String>{
          ...origin == null
              ? const <String, String>{}
              : <String, String>{
                  'access-control-allow-origin': origin,
                  'vary': 'origin',
                },
          'access-control-allow-methods': 'GET,POST,OPTIONS',
          'access-control-allow-headers': 'content-type',
          'cache-control': 'no-store',
          'x-content-type-options': 'nosniff',
        },
      );
    };

bool _isLoopbackOrigin(String value) {
  final origin = Uri.tryParse(value);
  return origin != null &&
      origin.isAbsolute &&
      const <String>{'http', 'https'}.contains(origin.scheme) &&
      const <String>{'localhost', '127.0.0.1', '::1'}.contains(origin.host) &&
      origin.userInfo.isEmpty &&
      (origin.path.isEmpty || origin.path == '/') &&
      !origin.hasQuery &&
      !origin.hasFragment;
}

Response _json(Map<String, Object?> body, {int status = 200}) => Response(
  status,
  headers: const <String, String>{
    'content-type': 'application/json; charset=utf-8',
  },
  body: jsonEncode(body),
);
