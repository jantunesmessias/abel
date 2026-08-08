import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('Scenario Lab run RPC contracts', () {
    test('round-trips bounded active, terminal and interrupted views', () {
      final initial = _snapshot(sequence: 0, state: ScenarioLabRunState.queued);
      final running = _snapshot(
        sequence: 1,
        state: ScenarioLabRunState.running,
      );
      final terminal = _snapshot(
        sequence: 2,
        state: ScenarioLabRunState.succeeded,
      );
      final result = ScenarioLabRunResult(
        finalSnapshot: terminal,
        startedAt: _time,
        completedAt: _time.add(const Duration(seconds: 2)),
        verificationState: VerificationState.notRun,
      );

      final reference = ScenarioLabRunReference(runId: _runId);
      expect(
        ScenarioLabRunReference.fromJson(reference.toJson()).toJson(),
        reference.toJson(),
      );
      final request = ScenarioLabRunObserveRequest(
        runId: _runId,
        afterSequence: -1,
        limit: 2,
      );
      expect(
        ScenarioLabRunObserveRequest.fromJson(request.toJson()).toJson(),
        request.toJson(),
      );

      final active = ScenarioLabRunObservation(
        runId: _runId,
        disposition: ScenarioLabRunDisposition.active,
        afterSequence: -1,
        current: running,
        observations: <ScenarioLabRunSnapshot>[initial, running],
        hasMore: false,
      );
      final interrupted = ScenarioLabRunObservation(
        runId: _runId,
        disposition: ScenarioLabRunDisposition.interrupted,
        afterSequence: 0,
        current: running,
        observations: <ScenarioLabRunSnapshot>[running],
        hasMore: false,
      );
      final completed = ScenarioLabRunObservation(
        runId: _runId,
        disposition: ScenarioLabRunDisposition.terminal,
        afterSequence: 0,
        current: terminal,
        observations: <ScenarioLabRunSnapshot>[running],
        hasMore: true,
        result: result,
      );
      for (final view in <ScenarioLabRunObservation>[
        active,
        interrupted,
        completed,
      ]) {
        expect(
          ScenarioLabRunObservation.fromJson(view.toJson()).toJson(),
          view.toJson(),
        );
      }
    });

    test(
      'rejects gaps, false pagination, mixed runs and invalid disposition',
      () {
        final initial = _snapshot(
          sequence: 0,
          state: ScenarioLabRunState.queued,
        );
        final running = _snapshot(
          sequence: 1,
          state: ScenarioLabRunState.running,
        );
        final terminal = _snapshot(
          sequence: 2,
          state: ScenarioLabRunState.succeeded,
        );

        expect(
          () => ScenarioLabRunObservation(
            runId: _runId,
            disposition: ScenarioLabRunDisposition.active,
            afterSequence: -1,
            current: running,
            observations: <ScenarioLabRunSnapshot>[running],
            hasMore: false,
          ),
          throwsArgumentError,
        );
        expect(
          () => ScenarioLabRunObservation(
            runId: _runId,
            disposition: ScenarioLabRunDisposition.active,
            afterSequence: -1,
            current: running,
            observations: <ScenarioLabRunSnapshot>[initial],
            hasMore: false,
          ),
          throwsArgumentError,
        );
        expect(
          () => ScenarioLabRunObservation(
            runId: _runId,
            disposition: ScenarioLabRunDisposition.active,
            afterSequence: -1,
            current: running,
            observations: <ScenarioLabRunSnapshot>[
              _snapshot(
                sequence: 0,
                state: ScenarioLabRunState.queued,
                runId: ScenarioLabRunId('other-run'),
              ),
            ],
            hasMore: true,
          ),
          throwsArgumentError,
        );
        expect(
          () => ScenarioLabRunObservation(
            runId: _runId,
            disposition: ScenarioLabRunDisposition.active,
            afterSequence: 2,
            current: terminal,
            observations: const <ScenarioLabRunSnapshot>[],
            hasMore: false,
          ),
          throwsArgumentError,
        );

        final wire = ScenarioLabRunReference(runId: _runId).toJson();
        wire['runId'] = 'tampered-run';
        expect(
          () => ScenarioLabRunReference.fromJson(wire),
          throwsFormatException,
        );
      },
    );

    test('caps observer requests and serialized observation pages', () {
      expect(
        () => ScenarioLabRunObserveRequest(runId: _runId, afterSequence: -2),
        throwsArgumentError,
      );
      expect(
        () => ScenarioLabRunObserveRequest(
          runId: _runId,
          afterSequence: -1,
          limit: 101,
        ),
        throwsArgumentError,
      );
      final wire = ScenarioLabRunObserveRequest(
        runId: _runId,
        afterSequence: -1,
      ).toJson();
      wire['limit'] = 0;
      wire['digest'] = Digest.semantic(<String, Object?>{
        for (final entry in wire.entries)
          if (entry.key != 'digest') entry.key: entry.value,
      }).value;
      expect(
        () => ScenarioLabRunObserveRequest.fromJson(wire),
        throwsArgumentError,
      );
    });

    test(
      'execution schema accepts run RPC documents and rejects open maps',
      () {
        final schema = jsonDecode(
          File(
            p.join(
              _repositoryRoot(),
              'schemas',
              'runtime',
              'scenario-lab-execution.schema.json',
            ),
          ).readAsStringSync(),
        );
        final validator = Draft202012Validator(schema as Object);
        final initial = _snapshot(
          sequence: 0,
          state: ScenarioLabRunState.queued,
        );
        final documents = <Map<String, Object?>>[
          ScenarioLabRunReference(runId: _runId).toJson(),
          ScenarioLabRunObserveRequest(
            runId: _runId,
            afterSequence: -1,
          ).toJson(),
          ScenarioLabRunObservation(
            runId: _runId,
            disposition: ScenarioLabRunDisposition.active,
            afterSequence: -1,
            current: initial,
            observations: <ScenarioLabRunSnapshot>[initial],
            hasMore: false,
          ).toJson(),
        ];
        for (final document in documents) {
          expect(validator.validate(document).isValid, isTrue);
          expect(
            validator.validate(<String, Object?>{
              ...document,
              'consumerMetadata': true,
            }).isValid,
            isFalse,
          );
        }
      },
    );

    test('host shutdown is a distinct cancelled wire cause', () {
      final shutdown = _shutdownSnapshot();
      final decoded = ScenarioLabRunSnapshot.fromJson(shutdown.toJson());
      expect(decoded.toJson(), shutdown.toJson());
      expect(decoded.terminalCause, ScenarioLabTerminalCause.hostShutdown);

      final schema = jsonDecode(
        File(
          p.join(
            _repositoryRoot(),
            'schemas',
            'runtime',
            'scenario-lab-execution.schema.json',
          ),
        ).readAsStringSync(),
      );
      expect(
        Draft202012Validator(
          schema as Object,
        ).validate(shutdown.toJson()).isValid,
        isTrue,
      );
      expect(
        () => ScenarioLabRunSnapshot(
          runId: shutdown.runId,
          startRequestDigest: shutdown.startRequestDigest,
          contentSetDigest: shutdown.contentSetDigest,
          catalogDigest: shutdown.catalogDigest,
          scenarioLabManifestDigest: shutdown.scenarioLabManifestDigest,
          scenarioId: shutdown.scenarioId,
          scriptId: shutdown.scriptId,
          sequence: shutdown.sequence,
          observedAt: shutdown.observedAt,
          state: ScenarioLabRunState.failed,
          runtimeInputs: shutdown.runtimeInputs,
          steps: shutdown.steps,
          cleanup: shutdown.cleanup,
          terminalCause: ScenarioLabTerminalCause.hostShutdown,
        ),
        throwsArgumentError,
      );
    });
  });
}

final ScenarioLabRunId _runId = ScenarioLabRunId('run-12345678');
final DateTime _time = DateTime.utc(2026, 8, 14, 12);

ScenarioLabRunSnapshot _snapshot({
  required int sequence,
  required ScenarioLabRunState state,
  ScenarioLabRunId? runId,
}) {
  final terminal = state.isTerminal;
  return ScenarioLabRunSnapshot(
    runId: runId ?? _runId,
    startRequestDigest: Digest.semantic('start'),
    contentSetDigest: Digest.semantic('content'),
    catalogDigest: Digest.semantic('catalog'),
    scenarioLabManifestDigest: Digest.semantic('lab'),
    scenarioId: ScenarioId('scenario-ready'),
    scriptId: ScenarioScriptId('script-ready'),
    sequence: sequence,
    observedAt: _time.add(Duration(seconds: sequence)),
    state: state,
    runtimeInputs: state == ScenarioLabRunState.queued
        ? null
        : ScenarioLabRuntimeInputBinding(
            executionFingerprintDigest: Digest.semantic('fingerprint'),
            executionTargetId: 'target-web',
          ),
    steps: <ScenarioLabStepSnapshot>[
      if (terminal)
        ScenarioLabStepSnapshot(
          stepId: 'step-ready',
          state: ScenarioLabStepState.succeeded,
          startedAt: _time,
          completedAt: _time.add(const Duration(seconds: 1)),
          terminalCause: ScenarioLabStepTerminalCause.completed,
        )
      else if (state == ScenarioLabRunState.queued)
        ScenarioLabStepSnapshot(
          stepId: 'step-ready',
          state: ScenarioLabStepState.pending,
        )
      else
        ScenarioLabStepSnapshot(
          stepId: 'step-ready',
          state: ScenarioLabStepState.running,
          startedAt: _time,
        ),
    ],
    cleanup: ScenarioLabCleanupResult(
      state: terminal
          ? ScenarioLabCleanupState.notRequired
          : ScenarioLabCleanupState.pending,
    ),
    terminalCause: terminal ? ScenarioLabTerminalCause.completed : null,
  );
}

ScenarioLabRunSnapshot _shutdownSnapshot() => ScenarioLabRunSnapshot(
  runId: _runId,
  startRequestDigest: Digest.semantic('start'),
  contentSetDigest: Digest.semantic('content'),
  catalogDigest: Digest.semantic('catalog'),
  scenarioLabManifestDigest: Digest.semantic('lab'),
  scenarioId: ScenarioId('scenario-ready'),
  scriptId: ScenarioScriptId('script-ready'),
  sequence: 2,
  observedAt: _time.add(const Duration(seconds: 2)),
  state: ScenarioLabRunState.cancelled,
  runtimeInputs: ScenarioLabRuntimeInputBinding(
    executionFingerprintDigest: Digest.semantic('fingerprint'),
    executionTargetId: 'target-web',
  ),
  steps: <ScenarioLabStepSnapshot>[
    ScenarioLabStepSnapshot(
      stepId: 'step-ready',
      state: ScenarioLabStepState.cancelled,
      startedAt: _time,
      completedAt: _time.add(const Duration(seconds: 1)),
      terminalCause: ScenarioLabStepTerminalCause.cancelled,
    ),
  ],
  cleanup: ScenarioLabCleanupResult(state: ScenarioLabCleanupState.notRequired),
  terminalCause: ScenarioLabTerminalCause.hostShutdown,
);

String _repositoryRoot() {
  var current = Directory.current.absolute;
  while (true) {
    if (File(p.join(current.path, 'pubspec.yaml')).existsSync() &&
        Directory(p.join(current.path, 'schemas')).existsSync()) {
      return current.path;
    }
    if (current.parent.path == current.path) {
      throw StateError('Repository root not found');
    }
    current = current.parent;
  }
}
