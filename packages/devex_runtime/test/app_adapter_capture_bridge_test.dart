import 'dart:io';

import 'package:devex_engine/devex_engine.dart';
import 'package:devex_runtime/devex_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/png_fixture.dart';

void main() {
  late Directory workspace;
  late _Clock clock;
  late AppAdapterCaptureBridge bridge;

  setUp(() async {
    workspace = Directory.systemTemp.createTempSync('devex-capture-bridge-');
    clock = _Clock(DateTime.utc(2026, 8, 9, 13));
    bridge = AppAdapterCaptureBridge(
      store: FileSystemWorkspaceStore(workspaceRoot: workspace.path),
      clock: clock,
      ids: _Ids(),
    );
    await bridge.start();
  });

  tearDown(() async {
    await bridge.close();
    workspace.deleteSync(recursive: true);
  });

  test(
    'one-shot origin-bound upload validates PNG and publishes CAS',
    () async {
      const targetOrigin = 'http://127.0.0.1:8181';
      final command = bridge.issue(
        requestId: 'request_12345678',
        sessionId: 'session_12345678',
        targetOrigin: Uri.parse(targetOrigin),
      );
      final completion = bridge.completions.first;
      final png = rgbaPng(
        width: 2,
        height: 1,
        pixels: const <int>[255, 0, 0, 255, 0, 255, 0, 255],
      );

      final response = await _put(
        command.uploadUri,
        origin: targetOrigin,
        bytes: png,
      );
      final receipt = await completion;

      expect(response, HttpStatus.created);
      expect(receipt.size, png.length);
      expect(receipt.width, 2);
      expect(receipt.height, 1);
      expect(
        File(
          p.join(
            workspace.path,
            '.dart_tool',
            'devex',
            'devex-kit',
            'cas',
            'sha256',
            receipt.artifactDigest.value.substring(7),
          ),
        ).readAsBytesSync(),
        png,
      );
      expect(
        bridge
            .status(
              sessionId: 'session_12345678',
              requestId: 'request_12345678',
            )
            .state,
        'completed',
      );
      expect(
        await _put(command.uploadUri, origin: targetOrigin, bytes: png),
        HttpStatus.forbidden,
      );
    },
  );

  test(
    'wrong origin, invalid PNG, expiry and session crossing fail closed',
    () async {
      final wrongOrigin = bridge.issue(
        requestId: 'request_wrong_origin',
        sessionId: 'session_12345678',
        targetOrigin: Uri.parse('http://127.0.0.1:8181'),
      );
      expect(
        await _put(
          wrongOrigin.uploadUri,
          origin: 'http://127.0.0.1:8282',
          bytes: const <int>[1, 2, 3],
        ),
        HttpStatus.forbidden,
      );

      final invalid = bridge.issue(
        requestId: 'request_invalid_png',
        sessionId: 'session_12345678',
        targetOrigin: Uri.parse('http://127.0.0.1:8181'),
      );
      expect(
        await _put(
          invalid.uploadUri,
          origin: 'http://127.0.0.1:8181',
          bytes: const <int>[1, 2, 3],
        ),
        HttpStatus.unprocessableEntity,
      );
      expect(
        bridge
            .status(
              sessionId: 'session_12345678',
              requestId: 'request_invalid_png',
            )
            .failureCode,
        'invalid_png',
      );
      expect(
        () => bridge.status(
          sessionId: 'session_crossed',
          requestId: 'request_invalid_png',
        ),
        throwsStateError,
      );

      final expired = bridge.issue(
        requestId: 'request_expired_123',
        sessionId: 'session_12345678',
        targetOrigin: Uri.parse('http://127.0.0.1:8181'),
      );
      clock.now = clock.now.add(const Duration(minutes: 3));
      expect(
        await _put(
          expired.uploadUri,
          origin: 'http://127.0.0.1:8181',
          bytes: const <int>[1, 2, 3],
        ),
        HttpStatus.forbidden,
      );
    },
  );

  test('terminal receipts do not consume the active upload quota', () async {
    final limited = AppAdapterCaptureBridge(
      store: FileSystemWorkspaceStore(workspaceRoot: workspace.path),
      clock: clock,
      ids: _Ids(),
      maxPending: 1,
    );
    await limited.start();
    try {
      const origin = 'http://127.0.0.1:8181';
      final first = limited.issue(
        requestId: 'request_first_123',
        sessionId: 'session_12345678',
        targetOrigin: Uri.parse(origin),
      );
      final png = rgbaPng(
        width: 1,
        height: 1,
        pixels: const <int>[1, 2, 3, 255],
      );
      expect(
        await _put(first.uploadUri, origin: origin, bytes: png),
        HttpStatus.created,
      );

      expect(
        () => limited.issue(
          requestId: 'request_second_123',
          sessionId: 'session_12345678',
          targetOrigin: Uri.parse(origin),
        ),
        returnsNormally,
      );
    } finally {
      await limited.close();
    }
  });
}

Future<int> _put(
  Uri uri, {
  required String origin,
  required List<int> bytes,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final request = await client.putUrl(uri);
    request.headers
      ..set('origin', origin)
      ..contentType = ContentType('image', 'png');
    request.add(bytes);
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

final class _Clock implements Clock {
  _Clock(this.now);

  DateTime now;

  @override
  DateTime nowUtc() => now;

  @override
  int monotonicMicroseconds() => now.microsecondsSinceEpoch;
}

final class _Ids implements IdGenerator {
  var next = 0;

  @override
  String nextId() => 'token_${++next}_12345678';
}
