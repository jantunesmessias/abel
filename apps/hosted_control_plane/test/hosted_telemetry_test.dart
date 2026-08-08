import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:devex_hosted_control_plane/hosted_control_plane.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  test(
    'OTLP middleware exports normalized routes and accepts W3C parent',
    () async {
      final collector = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = Completer<_Export>();
      final subscription = collector.listen((request) async {
        final bytes = await request.fold<List<int>>(
          <int>[],
          (output, chunk) => output..addAll(chunk),
        );
        if (!received.isCompleted) {
          received.complete(
            _Export(
              path: request.uri.path,
              contentType: request.headers.contentType?.mimeType,
              bytes: bytes,
            ),
          );
        }
        request.response.statusCode = 200;
        await request.response.close();
      });
      final telemetry = OpenTelemetryHostedTelemetry(
        collectorEndpoint: Uri.parse(
          'http://127.0.0.1:${collector.port}/v1/traces',
        ),
        serviceVersion: 'test-version',
        deploymentEnvironment: 'test',
        scheduledDelayMilliseconds: 10,
      );
      addTearDown(() async {
        await telemetry.shutdown();
        await subscription.cancel();
        await collector.close(force: true);
      });
      final handler = telemetry.middleware((request) async => Response(204));
      final response = await handler(
        Request(
          'POST',
          Uri.parse(
            'https://control.example.test/v1/remote/tenants/'
            'secret-tenant/workers/secret-worker/runs/secret-run/state',
          ),
          headers: const <String, String>{
            'traceparent':
                '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01',
          },
        ),
      );
      expect(response.statusCode, 204);
      final exported = await received.future.timeout(
        const Duration(seconds: 5),
      );
      expect(exported.path, '/v1/traces');
      expect(exported.contentType, 'application/x-protobuf');
      expect(exported.bytes, isNotEmpty);
      final payload = utf8.decode(exported.bytes, allowMalformed: true);
      expect(payload, contains('/v1/remote/tenants/:tenantId/'));
      expect(payload, isNot(contains('secret-tenant')));
      expect(payload, isNot(contains('secret-worker')));
      expect(payload, isNot(contains('secret-run')));
    },
  );
}

final class _Export {
  const _Export({
    required this.path,
    required this.contentType,
    required this.bytes,
  });

  final String path;
  final String? contentType;
  final List<int> bytes;
}
