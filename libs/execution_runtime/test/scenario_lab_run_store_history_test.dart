import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/src/lab/filesystem_scenario_lab_run_store.dart';
import 'package:execution_runtime/src/lab/scenario_lab_run_store.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:test/test.dart';

void main() {
  for (final entry in <String, ScenarioLabRunStore Function()>{
    'InMemoryScenarioLabRunStore': InMemoryScenarioLabRunStore.new,
    'FilesystemScenarioLabRunStore': _filesystemStore,
  }.entries) {
    group(entry.key, () {
      test(
        'accepts pending Evidence terminalization and append-only comparisons',
        () {
          final fixture = _registeredFixture(entry.value());
          final running = _nextSnapshot(
            fixture.starting,
            requiredEvidence: <RequiredEvidenceRunResult>[
              _collectedEvidence('visual-a'),
              _pendingEvidence('visual-b'),
            ],
            comparisons: <ScenarioComparisonResult>[_comparison('compare-a')],
          );
          fixture.store.append(running);

          final advanced = _nextSnapshot(
            running,
            requiredEvidence: <RequiredEvidenceRunResult>[
              _collectedEvidence('visual-a'),
              _failedEvidence('visual-b'),
            ],
            comparisons: <ScenarioComparisonResult>[
              _comparison('compare-a'),
              _comparison('compare-b'),
            ],
          );
          fixture.store.append(advanced);

          final stored = fixture.store.requireRun(fixture.initial.runId);
          expect(stored.latest.digest, advanced.digest);
          expect(
            stored.latest.requiredEvidence.map((item) => item.state),
            <RequiredEvidenceResultState>[
              RequiredEvidenceResultState.collected,
              RequiredEvidenceResultState.failed,
            ],
          );
          expect(stored.latest.comparisons, hasLength(2));
        },
      );

      test('rejects Evidence removal, substitution and binding rewrite', () {
        final fixture = _registeredFixture(entry.value());

        expect(
          () => fixture.store.append(
            _nextSnapshot(
              fixture.starting,
              requiredEvidence: <RequiredEvidenceRunResult>[
                _pendingEvidence('visual-a'),
              ],
            ),
          ),
          throwsArgumentError,
        );
        expect(
          () => fixture.store.append(
            _nextSnapshot(
              fixture.starting,
              requiredEvidence: <RequiredEvidenceRunResult>[
                _pendingEvidence('visual-a'),
                _pendingEvidence('visual-c'),
              ],
            ),
          ),
          throwsArgumentError,
        );
        expect(
          () => fixture.store.append(
            _nextSnapshot(
              fixture.starting,
              requiredEvidence: <RequiredEvidenceRunResult>[
                _pendingEvidence('visual-a', providerId: 'capture.other'),
                _pendingEvidence('visual-b'),
              ],
            ),
          ),
          throwsArgumentError,
        );
        expect(
          () => fixture.store.append(
            _nextSnapshot(
              fixture.starting,
              requiredEvidence: <RequiredEvidenceRunResult>[
                _pendingEvidence(
                  'visual-a',
                  freshness: EvidenceFreshness.invalid,
                ),
                _pendingEvidence('visual-b'),
              ],
            ),
          ),
          throwsArgumentError,
        );
        expect(
          fixture.store.requireRun(fixture.initial.runId).latest.sequence,
          1,
        );
      });

      test('rejects rewrite or regression after Evidence is terminal', () {
        final fixture = _registeredFixture(entry.value());
        final collected = _nextSnapshot(
          fixture.starting,
          requiredEvidence: <RequiredEvidenceRunResult>[
            _collectedEvidence('visual-a'),
            _pendingEvidence('visual-b'),
          ],
        );
        fixture.store.append(collected);

        expect(
          () => fixture.store.append(
            _nextSnapshot(
              collected,
              requiredEvidence: <RequiredEvidenceRunResult>[
                _pendingEvidence('visual-a'),
                _pendingEvidence('visual-b'),
              ],
            ),
          ),
          throwsStateError,
        );
        expect(
          () => fixture.store.append(
            _nextSnapshot(
              collected,
              requiredEvidence: <RequiredEvidenceRunResult>[
                _collectedEvidence('visual-a', artifactSeed: 'replacement'),
                _pendingEvidence('visual-b'),
              ],
            ),
          ),
          throwsStateError,
        );
        expect(
          () => fixture.store.append(
            _nextSnapshot(
              collected,
              requiredEvidence: <RequiredEvidenceRunResult>[
                _failedEvidence('visual-a'),
                _pendingEvidence('visual-b'),
              ],
            ),
          ),
          throwsStateError,
        );
        expect(
          fixture.store.requireRun(fixture.initial.runId).latest.digest,
          collected.digest,
        );
      });

      test('rejects removal or replacement of a published comparison', () {
        final fixture = _registeredFixture(entry.value());
        final published = _nextSnapshot(
          fixture.starting,
          comparisons: <ScenarioComparisonResult>[_comparison('compare-a')],
        );
        fixture.store.append(published);

        expect(
          () => fixture.store.append(
            _nextSnapshot(
              published,
              comparisons: const <ScenarioComparisonResult>[],
            ),
          ),
          throwsArgumentError,
        );
        expect(
          () => fixture.store.append(
            _nextSnapshot(
              published,
              comparisons: <ScenarioComparisonResult>[
                _comparison('compare-a', candidateSeed: 'replacement'),
              ],
            ),
          ),
          throwsStateError,
        );
        expect(
          () => fixture.store.append(
            _nextSnapshot(
              published,
              comparisons: <ScenarioComparisonResult>[_comparison('compare-b')],
            ),
          ),
          throwsArgumentError,
        );
        expect(
          fixture.store.requireRun(fixture.initial.runId).latest.digest,
          published.digest,
        );
      });

      test('fixes acceptance IDs and makes published results immutable', () {
        final fixture = _registeredFixture(entry.value());
        final passed = _nextSnapshot(
          fixture.starting,
          automatedAcceptance: <AutomatedAcceptanceResult>[
            _acceptance(VerificationState.passed),
          ],
        );
        fixture.store.append(passed);

        expect(
          () => fixture.store.append(
            _nextSnapshot(
              passed,
              automatedAcceptance: const <AutomatedAcceptanceResult>[],
            ),
          ),
          throwsArgumentError,
        );
        expect(
          () => fixture.store.append(
            _nextSnapshot(
              passed,
              automatedAcceptance: <AutomatedAcceptanceResult>[
                AutomatedAcceptanceResult(
                  criterionId: AutomatedAcceptanceCriterionId('replacement'),
                  verificationState: VerificationState.passed,
                ),
              ],
            ),
          ),
          throwsArgumentError,
        );
        expect(
          () => fixture.store.append(
            _nextSnapshot(
              passed,
              automatedAcceptance: <AutomatedAcceptanceResult>[
                _acceptance(VerificationState.failed),
              ],
            ),
          ),
          throwsStateError,
        );
      });

      test('controls are append-only and reset results are immutable', () {
        final fixture = _registeredFixture(entry.value());
        final read = _nextSnapshot(
          fixture.starting,
          controls: <ScenarioControlResult>[
            _control(ScenarioControlResultSource.read, value: false),
          ],
        );
        fixture.store.append(read);
        final written = _nextSnapshot(
          read,
          controls: <ScenarioControlResult>[
            _control(ScenarioControlResultSource.write, value: true),
          ],
        );
        fixture.store.append(written);

        expect(
          () => fixture.store.append(
            _nextSnapshot(written, controls: const <ScenarioControlResult>[]),
          ),
          throwsArgumentError,
        );

        final reset = _nextSnapshot(
          written,
          controls: <ScenarioControlResult>[
            _control(ScenarioControlResultSource.reset, value: false),
          ],
          cleanup: ScenarioLabCleanupResult(
            state: ScenarioLabCleanupState.running,
          ),
        );
        fixture.store.append(reset);
        expect(
          () => fixture.store.append(
            _nextSnapshot(
              reset,
              controls: <ScenarioControlResult>[
                _control(ScenarioControlResultSource.reset, value: true),
              ],
              cleanup: reset.cleanup,
            ),
          ),
          throwsStateError,
        );
      });

      test('cleanup cannot regress or skip its running terminalization', () {
        final fixture = _registeredFixture(entry.value());
        final cleaning = _nextSnapshot(
          fixture.starting,
          cleanup: ScenarioLabCleanupResult(
            state: ScenarioLabCleanupState.running,
          ),
        );
        fixture.store.append(cleaning);

        expect(
          () => fixture.store.append(
            _nextSnapshot(
              cleaning,
              cleanup: ScenarioLabCleanupResult(
                state: ScenarioLabCleanupState.pending,
              ),
            ),
          ),
          throwsStateError,
        );
        expect(
          () => fixture.store.append(
            _nextSnapshot(
              cleaning,
              cleanup: ScenarioLabCleanupResult(
                state: ScenarioLabCleanupState.notRequired,
              ),
            ),
          ),
          throwsStateError,
        );
        expect(
          () => fixture.store.append(
            _nextSnapshot(
              cleaning,
              cleanup: ScenarioLabCleanupResult(
                state: ScenarioLabCleanupState.running,
                resetControlIds: <ScenarioControlId>[
                  ScenarioControlId('unknown-control'),
                ],
              ),
            ),
          ),
          throwsArgumentError,
        );
      });

      test('register rejects a non-neutral queued snapshot', () {
        final store = entry.value();
        final seed = _initialFixture();
        final poisoned = _copySnapshot(
          seed.initial,
          steps: <ScenarioLabStepSnapshot>[
            ScenarioLabStepSnapshot(
              stepId: 'exercise',
              state: ScenarioLabStepState.succeeded,
              startedAt: _time(0),
              completedAt: _time(0),
              terminalCause: ScenarioLabStepTerminalCause.completed,
            ),
          ],
          controls: <ScenarioControlResult>[
            _control(ScenarioControlResultSource.read, value: true),
          ],
          requiredEvidence: <RequiredEvidenceRunResult>[
            _collectedEvidence('visual-a'),
            _pendingEvidence('visual-b'),
          ],
          automatedAcceptance: <AutomatedAcceptanceResult>[
            _acceptance(VerificationState.passed),
          ],
          comparisons: <ScenarioComparisonResult>[_comparison('compare-a')],
          cleanup: ScenarioLabCleanupResult(
            state: ScenarioLabCleanupState.succeeded,
          ),
        );

        expect(
          () =>
              store.register(request: seed.request, initialSnapshot: poisoned),
          throwsArgumentError,
        );
        expect(store.length, 0);
      });
    });
  }

  test('Filesystem replay rejects a digest-consistent Evidence regression', () {
    final root = Directory.systemTemp.createTempSync(
      'workspace-scenario-lab-history-tamper-',
    );
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final store = FilesystemScenarioLabRunStore(rootPath: root.path);
    final fixture = _registeredFixture(store);
    final collected = _nextSnapshot(
      fixture.starting,
      requiredEvidence: <RequiredEvidenceRunResult>[
        _collectedEvidence('visual-a'),
        _pendingEvidence('visual-b'),
      ],
    );
    store
      ..append(collected)
      ..append(_nextSnapshot(collected));

    final file = File(store.stateFilePath);
    final document =
        jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    final entries = document['entries']! as List<Object?>;
    final event = entries.last! as Map<String, Object?>;
    final payload = event['payload']! as Map<String, Object?>;
    final snapshot = payload['snapshot']! as Map<String, Object?>;
    snapshot['requiredEvidence'] = fixture.initial.requiredEvidence
        .map((item) => item.toJson())
        .toList();
    _replaceSemanticDigest(snapshot);
    _replaceSemanticDigest(event);
    document['headDigest'] = event['digest'];
    _replaceSemanticDigest(document);
    file.writeAsStringSync(
      '${const JcsCanonicalizer().canonicalize(document)}\n',
      flush: true,
    );

    expect(
      () => FilesystemScenarioLabRunStore(rootPath: root.path),
      throwsFormatException,
    );
  });

  test('Filesystem replay rejects a rehashed non-neutral initial state', () {
    final root = Directory.systemTemp.createTempSync(
      'workspace-scenario-lab-initial-tamper-',
    );
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final store = FilesystemScenarioLabRunStore(rootPath: root.path);
    final seed = _initialFixture();
    store.register(request: seed.request, initialSnapshot: seed.initial);
    final file = File(store.stateFilePath);
    final document =
        jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    final entries = document['entries']! as List<Object?>;
    final event = entries.single! as Map<String, Object?>;
    final payload = event['payload']! as Map<String, Object?>;
    final snapshot = payload['initialSnapshot']! as Map<String, Object?>;
    snapshot['controls'] = <Object?>[
      _control(ScenarioControlResultSource.read, value: true).toJson(),
    ];
    _replaceSemanticDigest(snapshot);
    _replaceSemanticDigest(event);
    document['headDigest'] = event['digest'];
    _replaceSemanticDigest(document);
    file.writeAsStringSync(
      '${const JcsCanonicalizer().canonicalize(document)}\n',
      flush: true,
    );

    expect(
      () => FilesystemScenarioLabRunStore(rootPath: root.path),
      throwsFormatException,
    );
  });

  test('Filesystem replay rejects rehashed acceptance regression', () {
    final root = Directory.systemTemp.createTempSync(
      'workspace-scenario-lab-acceptance-tamper-',
    );
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final store = FilesystemScenarioLabRunStore(rootPath: root.path);
    final fixture = _registeredFixture(store);
    final passed = _nextSnapshot(
      fixture.starting,
      automatedAcceptance: <AutomatedAcceptanceResult>[
        _acceptance(VerificationState.passed),
      ],
    );
    store
      ..append(passed)
      ..append(_nextSnapshot(passed));

    _rewriteLastSnapshot(File(store.stateFilePath), (snapshot) {
      snapshot['automatedAcceptance'] = <Object?>[
        _acceptance(VerificationState.notRun).toJson(),
      ];
    });

    expect(
      () => FilesystemScenarioLabRunStore(rootPath: root.path),
      throwsFormatException,
    );
  });

  test('Filesystem replay rejects rehashed control removal', () {
    final root = Directory.systemTemp.createTempSync(
      'workspace-scenario-lab-control-tamper-',
    );
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final store = FilesystemScenarioLabRunStore(rootPath: root.path);
    final fixture = _registeredFixture(store);
    final published = _nextSnapshot(
      fixture.starting,
      controls: <ScenarioControlResult>[
        _control(ScenarioControlResultSource.read, value: false),
      ],
    );
    store
      ..append(published)
      ..append(_nextSnapshot(published));

    _rewriteLastSnapshot(File(store.stateFilePath), (snapshot) {
      snapshot['controls'] = <Object?>[];
    });

    expect(
      () => FilesystemScenarioLabRunStore(rootPath: root.path),
      throwsFormatException,
    );
  });

  test('Filesystem replay rejects rehashed cleanup regression', () {
    final root = Directory.systemTemp.createTempSync(
      'workspace-scenario-lab-cleanup-tamper-',
    );
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final store = FilesystemScenarioLabRunStore(rootPath: root.path);
    final fixture = _registeredFixture(store);
    final cleaning = _nextSnapshot(
      fixture.starting,
      cleanup: ScenarioLabCleanupResult(state: ScenarioLabCleanupState.running),
    );
    store
      ..append(cleaning)
      ..append(_nextSnapshot(cleaning));

    _rewriteLastSnapshot(File(store.stateFilePath), (snapshot) {
      snapshot['cleanup'] = ScenarioLabCleanupResult(
        state: ScenarioLabCleanupState.pending,
      ).toJson();
    });

    expect(
      () => FilesystemScenarioLabRunStore(rootPath: root.path),
      throwsFormatException,
    );
  });
}

ScenarioLabRunStore _filesystemStore() {
  final root = Directory.systemTemp.createTempSync(
    'workspace-scenario-lab-history-',
  );
  addTearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });
  return FilesystemScenarioLabRunStore(rootPath: root.path);
}

final class _Fixture {
  const _Fixture({
    required this.store,
    required this.initial,
    required this.starting,
  });

  final ScenarioLabRunStore store;
  final ScenarioLabRunSnapshot initial;
  final ScenarioLabRunSnapshot starting;
}

_Fixture _registeredFixture(ScenarioLabRunStore store) {
  final seed = _initialFixture();
  store.register(request: seed.request, initialSnapshot: seed.initial);
  final starting = _nextSnapshot(
    seed.initial,
    state: ScenarioLabRunState.starting,
  );
  store.append(starting);
  return _Fixture(store: store, initial: seed.initial, starting: starting);
}

({ScenarioLabRunStartRequest request, ScenarioLabRunSnapshot initial})
_initialFixture() {
  final request = ScenarioLabRunStartRequest(
    requestId: ScenarioLabRunRequestId('request-1'),
    expectedContentSetDigest: _digest('content-set'),
    expectedScenarioLabManifestDigest: _digest('manifest'),
    scenarioId: ScenarioId('ready'),
    scriptId: ScenarioScriptId('exercise-ready'),
    requestedAt: _time(0),
  );
  final initial = ScenarioLabRunSnapshot(
    runId: ScenarioLabRunId('run-1'),
    startRequestDigest: request.digest,
    contentSetDigest: request.expectedContentSetDigest,
    catalogDigest: _digest('catalog'),
    scenarioLabManifestDigest: request.expectedScenarioLabManifestDigest,
    scenarioId: request.scenarioId,
    scriptId: request.scriptId,
    sequence: 0,
    observedAt: _time(0),
    state: ScenarioLabRunState.queued,
    steps: <ScenarioLabStepSnapshot>[
      ScenarioLabStepSnapshot(
        stepId: 'exercise',
        state: ScenarioLabStepState.pending,
      ),
    ],
    requiredEvidence: <RequiredEvidenceRunResult>[
      _pendingEvidence('visual-a'),
      _pendingEvidence('visual-b'),
    ],
    automatedAcceptance: <AutomatedAcceptanceResult>[
      _acceptance(VerificationState.notRun),
    ],
    cleanup: ScenarioLabCleanupResult(state: ScenarioLabCleanupState.pending),
  );
  return (request: request, initial: initial);
}

ScenarioLabRunSnapshot _nextSnapshot(
  ScenarioLabRunSnapshot previous, {
  ScenarioLabRunState state = ScenarioLabRunState.running,
  List<ScenarioLabStepSnapshot>? steps,
  List<ScenarioControlResult>? controls,
  List<RequiredEvidenceRunResult>? requiredEvidence,
  List<AutomatedAcceptanceResult>? automatedAcceptance,
  List<ScenarioComparisonResult>? comparisons,
  ScenarioLabCleanupResult? cleanup,
  ScenarioLabTerminalCause? terminalCause,
}) => ScenarioLabRunSnapshot(
  runId: previous.runId,
  startRequestDigest: previous.startRequestDigest,
  contentSetDigest: previous.contentSetDigest,
  catalogDigest: previous.catalogDigest,
  scenarioLabManifestDigest: previous.scenarioLabManifestDigest,
  scenarioId: previous.scenarioId,
  scriptId: previous.scriptId,
  sequence: previous.sequence + 1,
  observedAt: previous.observedAt.add(const Duration(minutes: 1)),
  state: state,
  runtimeInputs: previous.runtimeInputs ?? _runtimeInputs,
  steps: steps ?? previous.steps,
  controls: controls ?? previous.controls,
  requiredEvidence: requiredEvidence ?? previous.requiredEvidence,
  automatedAcceptance: automatedAcceptance ?? previous.automatedAcceptance,
  comparisons: comparisons ?? previous.comparisons,
  cleanup: cleanup ?? previous.cleanup,
  terminalCause: terminalCause,
);

ScenarioLabRunSnapshot _copySnapshot(
  ScenarioLabRunSnapshot source, {
  List<ScenarioLabStepSnapshot>? steps,
  List<ScenarioControlResult>? controls,
  List<RequiredEvidenceRunResult>? requiredEvidence,
  List<AutomatedAcceptanceResult>? automatedAcceptance,
  List<ScenarioComparisonResult>? comparisons,
  ScenarioLabCleanupResult? cleanup,
}) => ScenarioLabRunSnapshot(
  runId: source.runId,
  startRequestDigest: source.startRequestDigest,
  contentSetDigest: source.contentSetDigest,
  catalogDigest: source.catalogDigest,
  scenarioLabManifestDigest: source.scenarioLabManifestDigest,
  scenarioId: source.scenarioId,
  scriptId: source.scriptId,
  sequence: source.sequence,
  observedAt: source.observedAt,
  state: source.state,
  runtimeInputs: source.runtimeInputs,
  steps: steps ?? source.steps,
  controls: controls ?? source.controls,
  requiredEvidence: requiredEvidence ?? source.requiredEvidence,
  automatedAcceptance: automatedAcceptance ?? source.automatedAcceptance,
  comparisons: comparisons ?? source.comparisons,
  cleanup: cleanup ?? source.cleanup,
  terminalCause: source.terminalCause,
);

AutomatedAcceptanceResult _acceptance(VerificationState state) =>
    AutomatedAcceptanceResult(
      criterionId: AutomatedAcceptanceCriterionId('criterion-a'),
      verificationState: state,
    );

ScenarioControlResult _control(
  ScenarioControlResultSource source, {
  required bool value,
}) => ScenarioControlResult(
  controlId: ScenarioControlId('control-a'),
  source: source,
  value: BooleanScenarioControlValue(value),
);

RequiredEvidenceRunResult _pendingEvidence(
  String id, {
  String providerId = 'capture.web',
  EvidenceFreshness freshness = EvidenceFreshness.missing,
}) => RequiredEvidenceRunResult(
  requiredEvidenceId: RequiredEvidenceId(id),
  providerId: ModuleId(providerId),
  fidelity: RuntimeFidelity.hostNative,
  variantId: VariantId('phone'),
  freshness: freshness,
  state: RequiredEvidenceResultState.pending,
);

RequiredEvidenceRunResult _collectedEvidence(
  String id, {
  String artifactSeed = 'artifact',
}) => RequiredEvidenceRunResult(
  requiredEvidenceId: RequiredEvidenceId(id),
  providerId: ModuleId('capture.web'),
  fidelity: RuntimeFidelity.hostNative,
  variantId: VariantId('phone'),
  freshness: EvidenceFreshness.fresh,
  state: RequiredEvidenceResultState.collected,
  evidenceDigest: _digest('evidence-$id-$artifactSeed'),
  artifacts: <ScenarioEvidenceArtifactResult>[
    ScenarioEvidenceArtifactResult(
      artifactDigest: _digest('$artifactSeed-$id'),
      provenanceDigest: _digest('provenance-$id-$artifactSeed'),
      classification: ArtifactClassification.internal,
    ),
  ],
);

RequiredEvidenceRunResult _failedEvidence(String id) =>
    RequiredEvidenceRunResult(
      requiredEvidenceId: RequiredEvidenceId(id),
      providerId: ModuleId('capture.web'),
      fidelity: RuntimeFidelity.hostNative,
      variantId: VariantId('phone'),
      freshness: EvidenceFreshness.invalid,
      state: RequiredEvidenceResultState.failed,
      failure: ScenarioLabFailure(cause: ScenarioLabFailureCause.internalError),
    );

ScenarioComparisonResult _comparison(
  String id, {
  String candidateSeed = 'candidate',
}) => VisualScenarioComparisonResult(
  bindingId: ScenarioComparisonBindingId(id),
  requiredEvidenceId: RequiredEvidenceId('visual-a'),
  baselineDigest: _digest('baseline-$id'),
  candidateDigest: _digest('$candidateSeed-$id'),
  policyDigest: _digest('policy-$id'),
  verificationState: VerificationState.passed,
  comparedPixels: 16,
  changedPixels: 0,
  maxChannelDeltaObserved: 0,
);

final _runtimeInputs = ScenarioLabRuntimeInputBinding(
  executionFingerprintDigest: _digest('fingerprint'),
  executionTargetId: 'chrome',
);

Digest _digest(String value) => Digest.semantic(value);

DateTime _time(int minute) => DateTime.utc(2026, 8, 14, 12, minute);

void _replaceSemanticDigest(Map<String, Object?> document) {
  final body = Map<String, Object?>.of(document)..remove('digest');
  document['digest'] = Digest.semantic(body).value;
}

void _rewriteLastSnapshot(
  File file,
  void Function(Map<String, Object?> snapshot) mutate,
) {
  final document = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final entries = document['entries']! as List<Object?>;
  final event = entries.last! as Map<String, Object?>;
  final payload = event['payload']! as Map<String, Object?>;
  final snapshot = payload['snapshot']! as Map<String, Object?>;
  mutate(snapshot);
  _replaceSemanticDigest(snapshot);
  _replaceSemanticDigest(event);
  document['headDigest'] = event['digest'];
  _replaceSemanticDigest(document);
  file.writeAsStringSync(
    '${const JcsCanonicalizer().canonicalize(document)}\n',
    flush: true,
  );
}
