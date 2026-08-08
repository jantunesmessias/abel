import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('capture command is closed and conforms to its external schema', () {
    final command = AppAdapterCaptureCommand(
      requestId: 'request_12345678',
      sessionId: 'session_12345678',
      format: 'png',
      uploadUri: Uri.parse(
        'http://127.0.0.1:41000/capture-uploads/request_12345678?token=token_12345678',
      ),
      expiresAt: DateTime.utc(2026, 8, 9, 13),
      maxBytes: 1024 * 1024,
    );

    final decoded = AppAdapterCaptureCommand.fromJson(command.toJson());
    expect(decoded.uploadUri, command.uploadUri);
    final schema =
        jsonDecode(
              File(
                p.join(
                  _repositoryRoot(),
                  'schemas',
                  'v1',
                  'app-adapter-capture-command.schema.json',
                ),
              ).readAsStringSync(),
            )
            as Object;
    expect(
      Draft202012Validator(schema).validate(command.toJson()).isValid,
      isTrue,
    );
  });

  test('non-loopback handles and unknown fields fail closed', () {
    expect(
      () => AppAdapterCaptureCommand(
        requestId: 'request_12345678',
        sessionId: 'session_12345678',
        format: 'png',
        uploadUri: Uri.parse(
          'https://example.test/capture-uploads/request_12345678?token=token_12345678',
        ),
        expiresAt: DateTime.utc(2026, 8, 9, 13),
        maxBytes: 1024 * 1024,
      ),
      throwsFormatException,
    );
    final value = <String, Object?>{
      ...AppAdapterCaptureCommand(
        requestId: 'request_12345678',
        sessionId: 'session_12345678',
        format: 'png',
        uploadUri: Uri.parse(
          'http://127.0.0.1:41000/capture-uploads/request_12345678?token=token_12345678',
        ),
        expiresAt: DateTime.utc(2026, 8, 9, 13),
        maxBytes: 1024 * 1024,
      ).toJson(),
      'extra': true,
    };
    expect(
      () => AppAdapterCaptureCommand.fromJson(value),
      throwsFormatException,
    );
    for (final upload in <String>[
      'http://127.0.0.1:41000/capture-uploads/another_request?token=token_12345678',
      'http://127.0.0.1:41000/capture-uploads/request_12345678?token=token_12345678&token=token_abcdefgh',
      'http://user@127.0.0.1:41000/capture-uploads/request_12345678?token=token_12345678',
    ]) {
      expect(
        () => AppAdapterCaptureCommand(
          requestId: 'request_12345678',
          sessionId: 'session_12345678',
          format: 'png',
          uploadUri: Uri.parse(upload),
          expiresAt: DateTime.utc(2026, 8, 9, 13),
          maxBytes: 1024 * 1024,
        ),
        throwsFormatException,
      );
    }
  });
}

String _repositoryRoot() {
  var current = Directory.current.absolute;
  while (current.parent.path != current.path) {
    if (File(p.join(current.path, 'ARCHITECTURE.md')).existsSync()) {
      return current.path;
    }
    current = current.parent;
  }
  throw StateError('Repository root not found');
}
