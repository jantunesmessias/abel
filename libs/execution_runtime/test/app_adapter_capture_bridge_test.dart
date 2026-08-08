import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/png_fixture.dart';

void main() {
  late Directory workspace;
  late _Clock clock;
  late AppAdapterCaptureBridge bridge;

  setUp(() async {
    workspace = Directory.systemTemp.createTempSync(
      'workspace-capture-bridge-',
    );
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
            'workspace',
            'full-local',
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

  test(
    'close drains a chunked upload without CAS writes after return',
    () async {
      const origin = 'http://127.0.0.1:8181';
      final command = bridge.issue(
        requestId: 'request_chunked_close',
        sessionId: 'session_chunked_close',
        targetOrigin: Uri.parse(origin),
      );
      var completionCount = 0;
      final completions = bridge.completions.listen((_) {
        completionCount += 1;
      });
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 2);
      final request = await client.putUrl(command.uploadUri);
      request.headers
        ..set('origin', origin)
        ..contentType = ContentType('image', 'png');
      final png = rgbaPng(
        width: 2,
        height: 1,
        pixels: const <int>[1, 2, 3, 255, 4, 5, 6, 255],
      );
      request.add(png.sublist(0, png.length ~/ 2));
      await request.flush();
      await _waitForUploading(bridge, command);

      final closing = bridge.close();
      client.close(force: true);
      try {
        await request.close();
      } on Object {
        // The Host force-closes this deliberately incomplete request.
      }
      await closing.timeout(const Duration(seconds: 2));
      await completions.cancel();

      expect(bridge.isRunning, isFalse);
      expect(bridge.pendingCount, 0);
      expect(completionCount, 0);
      expect(
        () => bridge.status(
          sessionId: command.sessionId,
          requestId: command.requestId,
        ),
        throwsStateError,
      );
      final stateAfterClose = _stateFingerprint(bridge.store.stateRoot);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(_stateFingerprint(bridge.store.stateRoot), stateAfterClose);
      expect(
        stateAfterClose.keys.where(
          (path) => path.startsWith('${p.join('cas', 'sha256')}${p.separator}'),
        ),
        isEmpty,
      );
      await expectLater(bridge.start(), throwsStateError);
    },
  );

  test('receipt codec is canonical, strict, and digest fenced', () {
    final receipt = AppAdapterCaptureReceipt(
      requestId: 'request_codec_123',
      sessionId: 'session_codec_123',
      artifactDigest: Digest.semantic('artifact-codec'),
      pixelDigest: Digest.semantic('pixels-codec'),
      size: 1024,
      width: 32,
      height: 16,
      completedAt: DateTime.utc(2026, 8, 9, 13, 14, 15),
    );

    final decoded = AppAdapterCaptureReceipt.fromJson(
      jsonDecode(utf8.decode(receipt.canonicalBytes)),
      expectedDigest: receipt.digest,
    );

    expect(decoded.toJson(), receipt.toJson());
    expect(decoded.canonicalBytes, receipt.canonicalBytes);
    expect(decoded.digest, receipt.digest);

    final unknown = <String, Object?>{...receipt.toJson(), 'unexpected': true};
    expect(
      () => AppAdapterCaptureReceipt.fromJson(
        unknown,
        expectedDigest: Digest.bytes(
          utf8.encode(const JcsCanonicalizer().canonicalize(unknown)),
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => AppAdapterCaptureReceipt.fromJson(
        receipt.toJson(),
        expectedDigest: Digest.semantic('wrong-receipt'),
      ),
      throwsFormatException,
    );
    expect(
      () => AppAdapterCaptureReceipt.fromJson(<String, Object?>{
        ...receipt.toJson(),
        'mediaType': 'image/jpeg',
      }, expectedDigest: receipt.digest),
      throwsFormatException,
    );
    expect(
      () => AppAdapterCaptureReceipt.fromJson(<String, Object?>{
        ...receipt.toJson(),
        'completedAt': '2026-08-09T10:14:15-03:00',
      }, expectedDigest: receipt.digest),
      throwsFormatException,
    );
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

Future<void> _waitForUploading(
  AppAdapterCaptureBridge bridge,
  AppAdapterCaptureCommand command,
) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (bridge
            .status(sessionId: command.sessionId, requestId: command.requestId)
            .state ==
        'uploading') {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  throw StateError('Chunked capture upload did not start');
}

Map<String, Digest> _stateFingerprint(String stateRoot) {
  final root = Directory(stateRoot);
  if (!root.existsSync()) return const <String, Digest>{};
  final files = root
      .listSync(recursive: true, followLinks: false)
      .whereType<File>();
  return <String, Digest>{
    for (final file in files)
      p.relative(file.path, from: stateRoot): Digest.bytes(
        file.readAsBytesSync(),
      ),
  };
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
