import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('runtime overlays reject secret-like keys', () {
    expect(
      () => RuntimeConfigurationOverlay(<String, String>{
        'API_TOKEN': 'must-not-enter-authoring',
      }),
      throwsFormatException,
    );
    expect(
      RuntimeConfigurationOverlay(<String, String>{
        'API_BASE_URL': 'http://127.0.0.1:9000',
      }).values,
      containsPair('API_BASE_URL', 'http://127.0.0.1:9000'),
    );
  });

  test('execution target accepts only a canonical origin', () {
    ExecutionTarget(
      id: 'target',
      platform: TargetPlatform.web,
      origin: Uri.parse('http://127.0.0.1:8181/'),
      capabilities: const <CapabilityDescriptor>[],
    );
    for (final origin in <String>[
      'http://127.0.0.1:8181/path',
      'http://127.0.0.1:8181/?query=true',
      'http://user@127.0.0.1:8181/',
      'http://127.0.0.1:8181/#fragment',
      'ftp://127.0.0.1:8181/',
    ]) {
      expect(
        () => ExecutionTarget(
          id: 'target',
          platform: TargetPlatform.web,
          origin: Uri.parse(origin),
          capabilities: const <CapabilityDescriptor>[],
        ),
        throwsFormatException,
      );
    }
  });

  test('session documents are strict canonical public documents', () {
    final createdAt = DateTime.utc(2026, 8, 9, 12);
    final target = ExecutionTarget(
      id: 'target-1',
      platform: TargetPlatform.web,
      origin: Uri.parse('https://target.example.test'),
      capabilities: <CapabilityDescriptor>[
        CapabilityDescriptor(
          id: 'capture.png',
          version: 1,
          operations: const <String>{'request'},
        ),
      ],
    );
    final SessionCheckpoint checkpoint = SessionCheckpoint(
      sequence: 1,
      recordedAt: createdAt,
      reason: 'target ready',
    );
    final SessionSnapshot session = SessionSnapshot(
      id: 'session-1',
      launchProfileId: 'web-default',
      state: SessionState.ready,
      createdAt: createdAt,
      updatedAt: createdAt.add(const Duration(seconds: 1)),
      trace: <SessionTraceEntry>[
        SessionTraceEntry(
          sequence: 1,
          recordedAt: createdAt.add(const Duration(seconds: 1)),
          event: 'session.ready',
          data: const <String, Object?>{'targetId': 'target-1'},
        ),
      ],
      target: target,
    );
    final validator = Draft202012Validator(
      jsonDecode(
            File(
              p.join(
                _repositoryRoot(),
                'schemas',
                'runtime',
                'session-runtime.schema.json',
              ),
            ).readAsStringSync(),
          )
          as Object,
    );

    for (final document in <Map<String, Object?>>[
      checkpoint.toJson(),
      session.toJson(),
    ]) {
      final result = validator.validate(document);
      expect(result.isValid, isTrue, reason: '${result.issues}\n$document');
    }
    expect(
      SessionCheckpoint.fromJson(checkpoint.toJson()).digest,
      checkpoint.digest,
    );
    expect(SessionSnapshot.fromJson(session.toJson()).digest, session.digest);

    final tampered = session.toJson()..['state'] = 'stopped';
    expect(() => SessionSnapshot.fromJson(tampered), throwsFormatException);
  });

  test('Session rejects invalid chronology and terminal state', () {
    final createdAt = DateTime.utc(2026, 8, 9, 12);
    expect(
      () => SessionSnapshot(
        id: 'session-1',
        launchProfileId: 'web-default',
        state: SessionState.ready,
        createdAt: createdAt,
        updatedAt: createdAt.add(const Duration(seconds: 1)),
        trace: <SessionTraceEntry>[
          SessionTraceEntry(
            sequence: 2,
            recordedAt: createdAt.add(const Duration(seconds: 1)),
            event: 'session.ready',
            data: const <String, Object?>{},
          ),
          SessionTraceEntry(
            sequence: 1,
            recordedAt: createdAt,
            event: 'session.starting',
            data: const <String, Object?>{},
          ),
        ],
      ),
      throwsArgumentError,
    );
    expect(
      () => SessionSnapshot(
        id: 'session-1',
        launchProfileId: 'web-default',
        state: SessionState.failed,
        createdAt: createdAt,
        updatedAt: createdAt,
        trace: const <SessionTraceEntry>[],
      ),
      throwsArgumentError,
    );
  });
}

String _repositoryRoot() {
  var current = Directory.current.absolute;
  while (true) {
    final pubspec = File(p.join(current.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains(
          'name: experience_platform_workspace',
        )) {
      return current.path;
    }
    if (current.parent.path == current.path) {
      throw StateError('Repository root not found');
    }
    current = current.parent;
  }
}
