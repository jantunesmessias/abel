import 'dart:async';

import 'package:opentelemetry/api.dart' as otel_api;
import 'package:opentelemetry/sdk.dart' as otel_sdk;
import 'package:shelf/shelf.dart';

abstract interface class HostedTelemetry {
  Middleware get middleware;

  Future<void> shutdown();
}

final class NoopHostedTelemetry implements HostedTelemetry {
  const NoopHostedTelemetry();

  @override
  Middleware get middleware =>
      (inner) => inner;

  @override
  Future<void> shutdown() async {}
}

final class OpenTelemetryHostedTelemetry implements HostedTelemetry {
  OpenTelemetryHostedTelemetry({
    required Uri collectorEndpoint,
    required String serviceVersion,
    required String deploymentEnvironment,
    int scheduledDelayMilliseconds = 1000,
  }) {
    if (!const <String>{'http', 'https'}.contains(collectorEndpoint.scheme) ||
        collectorEndpoint.host.isEmpty ||
        collectorEndpoint.userInfo.isNotEmpty ||
        collectorEndpoint.query.isNotEmpty ||
        collectorEndpoint.fragment.isNotEmpty ||
        !collectorEndpoint.path.endsWith('/v1/traces')) {
      throw ArgumentError(
        'OTLP collector must be an HTTP(S) /v1/traces endpoint',
      );
    }
    _provider = otel_sdk.TracerProviderBase(
      resource: otel_sdk.Resource(<otel_api.Attribute>[
        otel_api.Attribute.fromString(
          otel_api.ResourceAttributes.serviceName,
          'control-plane-control-plane',
        ),
        otel_api.Attribute.fromString(
          otel_api.ResourceAttributes.serviceNamespace,
          'workspace',
        ),
        otel_api.Attribute.fromString(
          otel_api.ResourceAttributes.serviceVersion,
          serviceVersion,
        ),
        otel_api.Attribute.fromString(
          otel_api.ResourceAttributes.deploymentEnvironment,
          deploymentEnvironment,
        ),
      ]),
      processors: <otel_sdk.SpanProcessor>[
        otel_sdk.BatchSpanProcessor(
          otel_sdk.CollectorExporter(
            collectorEndpoint,
            timeoutMilliseconds: 5000,
          ),
          scheduledDelayMillis: scheduledDelayMilliseconds,
        ),
      ],
    );
    _tracer = _provider.getTracer(
      'workspace.hosted.http',
      version: serviceVersion,
    );
  }

  late final otel_sdk.TracerProviderBase _provider;
  late final otel_api.Tracer _tracer;
  final otel_api.W3CTraceContextPropagator _propagator =
      otel_api.W3CTraceContextPropagator();
  static const _HeaderGetter _headers = _HeaderGetter();

  @override
  Middleware get middleware =>
      (inner) => (request) async {
        final parent = _propagator.extract(
          otel_api.Context.root,
          request.headers,
          _headers,
        );
        final route = _routeName(request.url.pathSegments);
        final span = _tracer.startSpan(
          '${request.method} $route',
          context: parent,
          kind: otel_api.SpanKind.server,
          attributes: <otel_api.Attribute>[
            otel_api.Attribute.fromString(
              'http.request.method',
              request.method,
            ),
            otel_api.Attribute.fromString('http.route', route),
            otel_api.Attribute.fromString(
              'url.scheme',
              request.requestedUri.scheme,
            ),
          ],
        );
        try {
          final response = await inner(request);
          span.setAttribute(
            otel_api.Attribute.fromInt(
              'http.response.status_code',
              response.statusCode,
            ),
          );
          if (response.statusCode >= 500) {
            span.setStatus(otel_api.StatusCode.error, 'server response');
          } else {
            span.setStatus(otel_api.StatusCode.ok);
          }
          return response;
        } on Object catch (error, stackTrace) {
          span
            ..recordException(error, escaped: true, stackTrace: stackTrace)
            ..setStatus(
              otel_api.StatusCode.error,
              error.runtimeType.toString(),
            );
          rethrow;
        } finally {
          span.end();
        }
      };

  @override
  Future<void> shutdown() async {
    _provider.forceFlush();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _provider.shutdown();
  }

  String _routeName(List<String> segments) {
    if (segments.length == 1 && segments.single == 'healthz') return '/healthz';
    if (segments.length >= 4 &&
        segments[0] == 'v1' &&
        segments[1] == 'workspaces') {
      return '/v1/workspaces/:workspaceId/${segments.skip(3).join('/')}';
    }
    if (segments.length >= 4 &&
        segments[0] == 'v1' &&
        segments[1] == 'remote' &&
        segments[2] == 'runs') {
      return '/v1/remote/runs/:runId/${segments.skip(4).join('/')}';
    }
    if (segments.length >= 9 &&
        segments[0] == 'v1' &&
        segments[1] == 'remote' &&
        segments[2] == 'tenants') {
      return '/v1/remote/tenants/:tenantId/workers/:workerId/'
          'runs/:runId/${segments.skip(8).join('/')}';
    }
    if (segments.take(3).join('/') == 'v1/artifacts/upload-grants') {
      return '/v1/artifacts/upload-grants';
    }
    if (segments.take(3).join('/') == 'v1/remote/runs') {
      return '/v1/remote/runs';
    }
    return '/unmatched';
  }
}

final class _HeaderGetter
    implements otel_api.TextMapGetter<Map<String, String>> {
  const _HeaderGetter();

  @override
  String? get(Map<String, String> carrier, String key) => carrier[key];

  @override
  Iterable<String> keys(Map<String, String> carrier) => carrier.keys;
}
