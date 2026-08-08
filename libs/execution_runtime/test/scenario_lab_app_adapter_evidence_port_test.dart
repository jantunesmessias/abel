import 'dart:async';
import 'dart:io';

import 'package:execution_runtime/src/evidence/local_evidence_repository.dart';
import 'package:execution_runtime/src/host/app_adapter_capture_bridge.dart';
import 'package:execution_runtime/src/lab/scenario_lab_app_adapter_evidence_port.dart';
import 'package:execution_runtime/src/lab/scenario_lab_execution_ports.dart';
import 'package:execution_runtime/src/storage/filesystem_workspace_store.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:test/test.dart';

import 'support/png_fixture.dart';

void main() {
  late Directory workspace;
  late FileSystemWorkspaceStore store;
  late AppAdapterCaptureBridge bridge;
  late _Clock clock;

  setUp(() async {
    workspace = Directory.systemTemp.createTempSync('workspace-lab-evidence-');
    store = FileSystemWorkspaceStore(workspaceRoot: workspace.path);
    clock = _Clock();
    bridge = AppAdapterCaptureBridge(
      store: store,
      clock: clock,
      ids: _Ids('bridge'),
    );
    await bridge.start();
  });

  tearDown(() async {
    await bridge.close();
    if (workspace.existsSync()) workspace.deleteSync(recursive: true);
  });

  test(
    'uses readiness origin, verifies CAS and persists receipt Evidence',
    () async {
      var contextCalls = 0;
      final repository = LocalEvidenceRepository(store: store, clock: clock);
      final port = ScenarioLabAppAdapterEvidencePort(
        captureBridge: bridge,
        evidenceRepository: repository,
        ids: _Ids('evidence'),
        resolveContext: (runId, requirement, runtimeInputs) {
          contextCalls += 1;
          return ScenarioLabAppAdapterEvidenceContext(
            targetOrigin: _targetOrigin,
            executionFingerprint: _fingerprint,
            classification: ArtifactClassification.internal,
          );
        },
      );
      final grant = await port.issueCaptureUpload(
        runId: _runId,
        requirement: _requirement,
        runtimeInputs: _runtimeInputs,
        cancellation: _Cancellation(),
      );
      final png = rgbaPng(
        width: 2,
        height: 1,
        pixels: const <int>[255, 0, 0, 255, 0, 255, 0, 255],
      );

      expect(grant.sessionId, _runId.value);
      expect(
        await _put(grant.uploadUri, origin: _targetOrigin.origin, bytes: png),
        HttpStatus.created,
      );
      final collection = await port.consumeCaptureUpload(
        runId: _runId,
        requirement: _requirement,
        uploadGrant: grant,
        cancellation: _Cancellation(),
      );

      expect(contextCalls, 1);
      expect(collection, isNotNull);
      expect(collection!.evidence.fingerprint.digest, _fingerprint.digest);
      expect(
        collection.evidence.artifacts.single.classification,
        ArtifactClassification.internal,
      );
      expect(
        repository.readLatestEvidence()?.digest,
        collection.evidence.digest,
      );
      expect(
        store.readBlob(Digest.semantic(collection.uploadReceipt.toJson())),
        isNotNull,
        reason: 'receipt provenance is retained by its advertised digest',
      );
      final repeated = await port.consumeCaptureUpload(
        runId: _runId,
        requirement: _requirement,
        uploadGrant: grant,
        cancellation: _Cancellation(),
      );
      expect(repeated?.evidence.digest, collection.evidence.digest);

      await port.cleanupRun(_runId);
      expect(
        () => bridge.status(
          sessionId: grant.sessionId,
          requestId: grant.requestId,
        ),
        throwsStateError,
      );
    },
  );

  test('Host policy and fingerprint mismatches allocate no upload', () async {
    final repository = LocalEvidenceRepository(store: store, clock: clock);
    final denied = ScenarioLabAppAdapterEvidencePort(
      captureBridge: bridge,
      evidenceRepository: repository,
      ids: _Ids('denied'),
      resolveContext: (runId, requirement, runtimeInputs) =>
          ScenarioLabAppAdapterEvidenceContext(
            targetOrigin: _targetOrigin,
            executionFingerprint: _fingerprint,
            classification: ArtifactClassification.sensitive,
          ),
    );
    await expectLater(
      denied.issueCaptureUpload(
        runId: _runId,
        requirement: _requirement,
        runtimeInputs: _runtimeInputs,
        cancellation: _Cancellation(),
      ),
      throwsA(isA<ScenarioLabEvidencePolicyDenied>()),
    );
    expect(bridge.pendingCount, 0);

    final mismatched = ScenarioLabAppAdapterEvidencePort(
      captureBridge: bridge,
      evidenceRepository: repository,
      ids: _Ids('mismatch'),
      resolveContext: (runId, requirement, runtimeInputs) =>
          ScenarioLabAppAdapterEvidenceContext(
            targetOrigin: _targetOrigin,
            executionFingerprint: _fingerprint,
            classification: ArtifactClassification.internal,
          ),
    );
    await expectLater(
      mismatched.issueCaptureUpload(
        runId: _runId,
        requirement: _requirement,
        runtimeInputs: ScenarioLabRuntimeInputBinding(
          executionFingerprintDigest: Digest.semantic('wrong-fingerprint'),
          executionTargetId: 'chrome',
        ),
        cancellation: _Cancellation(),
      ),
      throwsA(isA<ScenarioLabEvidenceInvalidInput>()),
    );
    expect(bridge.pendingCount, 0);
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

final _runId = ScenarioLabRunId('run-evidence-1');
final _targetOrigin = Uri.parse('http://127.0.0.1:8181');
final _catalogDigest = Digest.semantic('catalog');
final _fingerprint = ExecutionFingerprint(
  catalogDigest: _catalogDigest,
  launchProfileId: 'app-web',
  targetId: 'chrome',
  platform: 'web',
  renderer: 'canvaskit',
  runtimeFidelity: RuntimeFidelity.hostNative,
  backendMode: BackendMode.none,
  networkContainment: NetworkContainment.unconstrained,
  bootstrapAssessment: BootstrapAssessment.controlled,
  toolchain: const <String, String>{'flutter': '3.44.8'},
  capabilities: const <String>{'capture.app-adapter'},
  inputDigests: <String, Digest>{'catalog': _catalogDigest},
  policies: const <String, String>{'capture': 'visual-v1'},
);
final _runtimeInputs = ScenarioLabRuntimeInputBinding(
  executionFingerprintDigest: _fingerprint.digest,
  executionTargetId: 'chrome',
);
final _requirement = RequiredEvidenceDefinition(
  id: RequiredEvidenceId('ready-visual'),
  scenarioId: ScenarioId('ready'),
  providerId: ModuleId('capture.app-adapter'),
  fidelity: RuntimeFidelity.hostNative,
  variantId: VariantId('desktop'),
  freshness: EvidenceFreshness.fresh,
  allowedClassifications: <ArtifactClassification>{
    ArtifactClassification.internal,
  },
  evidencePolicyId: EvidencePolicyId('visual-v1'),
  comparisonPolicy: VisualComparisonPolicyReference(
    VisualComparisonPolicyId('pixel-v1'),
  ),
);

final class _Clock implements Clock {
  @override
  int monotonicMicroseconds() => 0;

  @override
  DateTime nowUtc() => DateTime.utc(2026, 8, 14, 12);
}

final class _Ids implements IdGenerator {
  _Ids(this.prefix);

  final String prefix;
  var next = 0;

  @override
  String nextId() => '${prefix}_token_${(++next).toString().padLeft(8, '0')}';
}

final class _Cancellation implements ScenarioLabCancellationSignal {
  final Completer<void> _never = Completer<void>();

  @override
  bool get isCancelled => false;

  @override
  Future<void> get whenCancelled => _never.future;
}
