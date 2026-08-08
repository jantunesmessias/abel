import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('round-trips a closed target readiness record through its schema', () {
    final record = TargetReadinessRecord(
      launchAttemptId: TargetLaunchAttemptId('attempt_0123456789abcdef'),
      targetId: 'sample-web',
      launchProfileId: 'sample-web',
      origin: Uri.parse('http://127.0.0.1:8080/'),
      processId: 42,
    );

    expect(record.origin.toString(), 'http://127.0.0.1:8080');
    expect(_validator().validate(record.toJson()).isValid, isTrue);
    expect(
      TargetReadinessRecord.fromJson(
        jsonDecode(jsonEncode(record.toJson())),
      ).toJson(),
      record.toJson(),
    );
  });

  test('rejects unbound, non-loopback, noncanonical and tampered records', () {
    expect(
      () => TargetReadinessRecord(
        launchAttemptId: TargetLaunchAttemptId('attempt_0123456789abcdef'),
        targetId: 'sample-web',
        launchProfileId: 'sample-web',
        origin: Uri.parse('https://example.test:8080'),
        processId: 42,
      ),
      throwsFormatException,
    );
    final record = TargetReadinessRecord(
      launchAttemptId: TargetLaunchAttemptId('attempt_0123456789abcdef'),
      targetId: 'sample-web',
      launchProfileId: 'sample-web',
      origin: Uri.parse('http://127.0.0.1:8080'),
      processId: 42,
    ).toJson();
    expect(
      () => TargetReadinessRecord.fromJson(<String, Object?>{
        ...record,
        'origin': 'http://127.0.0.1:8080/',
      }),
      throwsFormatException,
    );
    expect(
      () => TargetReadinessRecord.fromJson(<String, Object?>{
        ...record,
        'processId': 43,
      }),
      throwsFormatException,
    );
    expect(
      () => TargetReadinessRecord.fromJson(<String, Object?>{
        ...record,
        'extra': true,
      }),
      throwsFormatException,
    );
  });
}

Draft202012Validator _validator() => Draft202012Validator(
  jsonDecode(
        File(
          p.join(
            _repositoryRoot(),
            'schemas',
            'runtime',
            'target-readiness-record.schema.json',
          ),
        ).readAsStringSync(),
      )
      as Object,
);

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
