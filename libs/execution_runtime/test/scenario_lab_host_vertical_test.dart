import 'dart:async';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

void main() {
  test(
    'Host runs a fenced control script through the private relay and recovers it',
    () async {
      const token = '0123456789abcdef0123456789abcdef';
      final temporary = Directory.systemTemp.createTempSync(
        'workspace-scenario-lab-host-',
      );
      final studioRoot = Directory(p.join(temporary.path, 'studio'))
        ..createSync();
      File(p.join(studioRoot.path, 'index.html')).writeAsStringSync('studio');
      final studio = StaticWebOriginServer(rootDirectory: studioRoot.path);
      await studio.start();
      final targetScript = _writeTargetProcess(temporary);
      final catalog = _catalog();
      final manifest = _manifest(catalog);
      final application = WorkspaceHost(
        studioOrigin: studio.origin,
        sessionToken: token,
        workspaceRoot: temporary.path,
        launchProfiles: <LaunchProfile>[
          LaunchProfile(
            id: 'lab-web',
            applicationId: ApplicationId('app'),
            platform: TargetPlatform.web,
            command: Platform.resolvedExecutable,
            arguments: <String>[
              '--packages=${p.join(_repositoryRoot(), '.dart_tool', 'package_config.json')}',
              targetScript.path,
            ],
            workingDirectory: '.',
            overlay: RuntimeConfigurationOverlay(const <String, String>{}),
            bootstrapPolicy: ApplicationBootstrapPolicy(
              const <String, BootstrapDependencyPolicy>{},
            ),
          ),
        ],
        gatewaySidecarCommand: Platform.resolvedExecutable,
        gatewaySidecarArguments: <String>[
          p.join(
            _repositoryRoot(),
            'apps',
            'gateway_sidecar',
            'bin',
            'gateway_sidecar.dart',
          ),
        ],
        gatewaySidecarWorkingDirectory: _repositoryRoot(),
        workspaceCatalog: catalog,
        workspaceScenarioLabManifest: manifest,
      );
      await application.start();
      addTearDown(() async {
        await application.close();
        await studio.close();
        temporary.deleteSync(recursive: true);
      });

      final rpc = await _RpcClient.connect(application.rpc, studio.origin);
      addTearDown(rpc.close);
      final initialized = await rpc.initialize();
      final capabilities =
          (initialized.result! as Map<String, Object?>)['capabilities']!
              as List<Object?>;
      expect(
        capabilities,
        containsAll(<String>[
          'lab.start',
          'lab.get',
          'lab.cancel',
          'lab.reattach',
          'lab.relay.describe',
          'lab.relay.v2.describe',
          'lab.relay.hello',
          'lab.relay.next',
          'lab.relay.result',
        ]),
      );

      final identity = application.workspace!.contentSetIdentity;
      final stale = ScenarioLabRunStartRequest(
        requestId: ScenarioLabRunRequestId('request-stale'),
        expectedContentSetDigest: Digest.semantic('stale-content'),
        expectedScenarioLabManifestDigest: manifest.digest,
        scenarioId: _scenarioId,
        scriptId: _scriptId,
        requestedAt: DateTime.utc(2026, 8, 14, 12),
      );
      final staleResponse = await rpc.call('lab.start', stale.toJson());
      expect(staleResponse.error?.code, -32003);
      expect(application.scenarioLab!.target.activeProcessCount, 0);

      final request = ScenarioLabRunStartRequest(
        requestId: ScenarioLabRunRequestId('request-valid'),
        expectedContentSetDigest: identity.contentSetDigest,
        expectedScenarioLabManifestDigest: manifest.digest,
        scenarioId: _scenarioId,
        scriptId: _scriptId,
        requestedAt: DateTime.utc(2026, 8, 14, 12),
      );
      final startResponse = await rpc.call('lab.start', request.toJson());
      expect(startResponse.isSuccess, isTrue, reason: '${startResponse.error}');
      final started = ScenarioLabRunSnapshot.fromJson(startResponse.result);
      expect(started.state, ScenarioLabRunState.queued);

      final description = await _waitForRelay(
        rpc,
        started.runId,
        request.digest,
      );
      final descriptor = description.descriptor!;
      expect(description.startRequestDigest, request.digest);
      expect(description.runtimeInputs, isNotNull);
      expect(description.gatewayDataOrigin, isNull);
      expect(descriptor.targetId, 'target-web');
      expect(descriptor.origin.host, anyOf('127.0.0.1', 'localhost'));
      final hello = AppAdapterRelayHello(
        runId: started.runId,
        adapterInstanceId: 'adapter-instance-1',
        sequence: 0,
        nonce: descriptor.nonce,
        capabilities: <AppAdapterCapabilityReference>[_capability],
      );
      final helloResponse = await rpc.call(
        'lab.relay.hello',
        ScenarioLabRelayHelloSubmission(
          descriptorDigest: descriptor.digest,
          hello: hello,
        ).toJson(),
      );
      expect(helloResponse.isSuccess, isTrue);

      var controlValue = false;
      var sequence = 0;
      for (var index = 0; index < 4; index += 1) {
        final response = await rpc.call(
          'lab.relay.next',
          ScenarioLabRelayPollRequest(
            runId: started.runId,
            descriptorDigest: descriptor.digest,
            afterSequence: sequence,
            waitMs: 5000,
          ).toJson(),
        );
        expect(response.isSuccess, isTrue, reason: '${response.error}');
        final poll = ScenarioLabRelayPollResponse.fromJson(response.result);
        expect(poll.state, ScenarioLabRelayPollState.command);
        final command = poll.command!;
        final AppAdapterRelayResult result;
        switch (command) {
          case ReadAppAdapterRelayCommand():
            result = ReadAppAdapterRelayResult(
              runId: command.runId,
              commandId: command.commandId,
              sequence: command.sequence,
              nonce: command.nonce,
              state: AppAdapterRelayResultState.succeeded,
              value: BooleanScenarioControlValue(controlValue),
            );
          case WriteAppAdapterRelayCommand(
            value: final BooleanScenarioControlValue requested,
          ):
            controlValue = requested.value;
            result = WriteAppAdapterRelayResult(
              runId: command.runId,
              commandId: command.commandId,
              sequence: command.sequence,
              nonce: command.nonce,
              state: AppAdapterRelayResultState.succeeded,
              value: requested,
            );
          case ResetAppAdapterRelayCommand():
            controlValue = false;
            result = ResetAppAdapterRelayResult(
              runId: command.runId,
              commandId: command.commandId,
              sequence: command.sequence,
              nonce: command.nonce,
              state: AppAdapterRelayResultState.succeeded,
              value: const BooleanScenarioControlValue(false),
            );
          case CaptureAppAdapterRelayCommand():
            fail('control-only plan emitted a capture command');
          default:
            fail('control-only plan emitted an unsupported command');
        }
        final resultResponse = await rpc.call(
          'lab.relay.result',
          ScenarioLabRelayResultSubmission(
            descriptorDigest: descriptor.digest,
            result: result,
          ).toJson(),
        );
        expect(
          resultResponse.isSuccess,
          isTrue,
          reason: '${resultResponse.error}',
        );
        sequence = command.sequence;
      }
      expect(controlValue, isFalse, reason: 'cleanup must reset the control');

      final terminal = await _waitForTerminal(rpc, started.runId);
      expect(terminal.current.state, ScenarioLabRunState.succeeded);
      expect(
        terminal.current.terminalCause,
        ScenarioLabTerminalCause.completed,
      );
      expect(terminal.current.cleanup.state, ScenarioLabCleanupState.succeeded);
      expect(
        terminal.current.automatedAcceptance.map(
          (item) => item.verificationState,
        ),
        everyElement(VerificationState.passed),
      );
      expect(terminal.result?.verificationState, VerificationState.passed);
      expect(application.scenarioLab!.target.activeProcessCount, 0);
      expect(application.scenarioLab!.host.relay.activeCount, 0);

      final retry = await rpc.call('lab.start', request.toJson());
      final retrySnapshot = ScenarioLabRunSnapshot.fromJson(retry.result);
      expect(retrySnapshot.digest, terminal.current.digest);
      expect(application.scenarioLab!.target.activeProcessCount, 0);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'Host shutdown drains the active Lab before process, relay, and bridge',
    () async {
      const token = '0123456789abcdef0123456789abcdef';
      final temporary = Directory.systemTemp.createTempSync(
        'workspace-scenario-lab-shutdown-',
      );
      final studioRoot = Directory(p.join(temporary.path, 'studio'))
        ..createSync();
      File(p.join(studioRoot.path, 'index.html')).writeAsStringSync('studio');
      final studio = StaticWebOriginServer(rootDirectory: studioRoot.path);
      await studio.start();
      final targetScript = _writeTargetProcess(temporary);
      final catalog = _catalog();
      final manifest = _manifest(catalog);
      final application = WorkspaceHost(
        studioOrigin: studio.origin,
        sessionToken: token,
        workspaceRoot: temporary.path,
        launchProfiles: <LaunchProfile>[
          LaunchProfile(
            id: 'lab-web',
            applicationId: ApplicationId('app'),
            platform: TargetPlatform.web,
            command: Platform.resolvedExecutable,
            arguments: <String>[
              '--packages=${p.join(_repositoryRoot(), '.dart_tool', 'package_config.json')}',
              targetScript.path,
            ],
            workingDirectory: '.',
            overlay: RuntimeConfigurationOverlay(const <String, String>{}),
            bootstrapPolicy: ApplicationBootstrapPolicy(
              const <String, BootstrapDependencyPolicy>{},
            ),
          ),
        ],
        gatewaySidecarCommand: Platform.resolvedExecutable,
        gatewaySidecarArguments: <String>[
          p.join(
            _repositoryRoot(),
            'apps',
            'gateway_sidecar',
            'bin',
            'gateway_sidecar.dart',
          ),
        ],
        gatewaySidecarWorkingDirectory: _repositoryRoot(),
        workspaceCatalog: catalog,
        workspaceScenarioLabManifest: manifest,
      );
      await application.start();
      final rpc = await _RpcClient.connect(application.rpc, studio.origin);
      addTearDown(() async {
        await rpc.close();
        await application.close();
        await studio.close();
        if (temporary.existsSync()) temporary.deleteSync(recursive: true);
      });
      expect((await rpc.initialize()).isSuccess, isTrue);

      final identity = application.workspace!.contentSetIdentity;
      final request = ScenarioLabRunStartRequest(
        requestId: ScenarioLabRunRequestId('request-host-shutdown'),
        expectedContentSetDigest: identity.contentSetDigest,
        expectedScenarioLabManifestDigest: manifest.digest,
        scenarioId: _scenarioId,
        scriptId: _scriptId,
        requestedAt: DateTime.utc(2026, 8, 14, 12),
      );
      final response = await rpc.call('lab.start', request.toJson());
      expect(response.isSuccess, isTrue, reason: '${response.error}');
      final started = ScenarioLabRunSnapshot.fromJson(response.result);
      await _waitForRelay(rpc, started.runId, request.digest);
      final lab = application.scenarioLab!;
      expect(lab.host.execution.activeRunCount, 1);
      expect(lab.target.activeProcessCount, 1);
      expect(lab.host.relay.activeCount, 1);
      expect(application.captureBridge.isRunning, isTrue);

      await application.close();

      final stored = lab.runStore.requireRun(started.runId);
      expect(stored.result, isNotNull);
      expect(stored.latest.state, ScenarioLabRunState.cancelled);
      expect(
        stored.latest.terminalCause,
        ScenarioLabTerminalCause.hostShutdown,
      );
      expect(lab.host.execution.activeRunCount, 0);
      expect(lab.host.execution.isClosed, isTrue);
      expect(lab.target.activeProcessCount, 0);
      expect(lab.target.activeSessionCount, 0);
      expect(lab.host.relay.activeCount, 0);
      expect(application.captureBridge.pendingCount, 0);
      expect(application.captureBridge.isRunning, isFalse);

      final journal = File(lab.runStore.stateFilePath);
      final committedJournal = journal.readAsBytesSync();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(journal.readAsBytesSync(), committedJournal);
      expect(
        lab.runStore.requireRun(started.runId).result!.digest,
        stored.result!.digest,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

final ScenarioId _scenarioId = ScenarioId('ready');
final ScenarioScriptId _scriptId = ScenarioScriptId('exercise-ready');
final ScenarioExecutionBindingId _bindingId = ScenarioExecutionBindingId(
  'ready-web',
);
final ScenarioControlId _controlId = ScenarioControlId('feature-ready');
final AppAdapterCapabilityReference _capability = AppAdapterCapabilityReference(
  id: AppAdapterCapabilityId('sample.controls'),
  version: 1,
);

CatalogManifest _catalog() {
  final layout = ConsumerLayout.standard;
  final workspaceId = WorkspaceId('workspace');
  final applicationId = ApplicationId('app');
  return CatalogManifest(
    distribution: DistributionDescriptor(
      id: 'full-local',
      displayName: 'Abel',
      coreCompatibility: '^0.1.0',
      defaultLayout: layout,
    ),
    layout: layout,
    workspace: Workspace(id: workspaceId, displayName: 'Workspace'),
    applications: <Application>[
      Application(
        id: applicationId,
        workspaceId: workspaceId,
        displayName: 'App',
        root: '.',
        target: 'web',
      ),
    ],
    journeys: const <Journey>[],
    scenarios: <Scenario>[
      Scenario(id: _scenarioId, applicationId: applicationId, title: 'Ready'),
    ],
    transitions: const <Transition>[],
    executionBindings: <ScenarioExecutionBinding>[
      ScenarioExecutionBinding(
        id: _bindingId,
        scenarioId: _scenarioId,
        targetId: 'target-web',
        launchProfileId: 'lab-web',
      ),
    ],
  );
}

ScenarioLabManifest _manifest(CatalogManifest catalog) => ScenarioLabManifest(
  catalog: catalog,
  appAdapterCapabilities: <CapabilityDescriptor>[
    CapabilityDescriptor(
      id: 'sample.controls',
      version: 1,
      operations: <String>{'read', 'write', 'reset'},
    ),
  ],
  controls: <ScenarioControlDefinition>[
    ScenarioControlDefinition(
      id: _controlId,
      scenarioId: _scenarioId,
      displayName: 'Feature ready',
      capability: _capability,
      readOperationId: CapabilityOperationId('read'),
      writeOperationId: CapabilityOperationId('write'),
      resetOperationId: CapabilityOperationId('reset'),
      domain: BooleanScenarioControlDomain(defaultValue: false),
    ),
  ],
  operations: <ScenarioLabOperationDefinition>[
    AssignControlOperationDefinition(
      id: ScenarioLabOperationId('assign-ready'),
      scenarioId: _scenarioId,
      controlId: _controlId,
      value: const BooleanScenarioControlValue(true),
    ),
  ],
  scripts: <ScenarioScriptDefinition>[
    ScenarioScriptDefinition(
      id: _scriptId,
      scenarioId: _scenarioId,
      displayName: 'Exercise ready',
      timeoutMs: 30000,
      timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
      cancellationPolicy: ScenarioScriptCancellationPolicy.immediate,
      steps: <ScenarioScriptStep>[
        ExecutionBindingScenarioScriptStep(
          id: 'attach',
          timeoutMs: 10000,
          timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
          bindingId: _bindingId,
        ),
        OperationScenarioScriptStep(
          id: 'assign-ready',
          timeoutMs: 10000,
          timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
          operationId: ScenarioLabOperationId('assign-ready'),
        ),
      ],
    ),
  ],
  automatedAcceptanceCriteria: <AutomatedAcceptanceCriterion>[
    ScriptSucceededAcceptanceCriterion(
      id: AutomatedAcceptanceCriterionId('script-succeeded'),
      scenarioId: _scenarioId,
      displayName: 'Script succeeded',
      scriptId: _scriptId,
    ),
    ControlEqualsAcceptanceCriterion(
      id: AutomatedAcceptanceCriterionId('feature-observed'),
      scenarioId: _scenarioId,
      displayName: 'Feature was observed',
      controlId: _controlId,
      expectedValue: const BooleanScenarioControlValue(true),
    ),
  ],
  requiredEvidence: const <RequiredEvidenceDefinition>[],
  comparisonBindings: const <ScenarioComparisonBinding>[],
  visualComparisonPolicies: const <VisualComparisonPolicy>[],
  semanticComparisonPolicies: const <SemanticComparisonPolicy>[],
  humanApprovalRequirements: const <HumanApprovalRequirement>[],
  supplementalArtifacts: const <SupplementalArtifactReference>[],
  plans: <ScenarioLabPlan>[
    ScenarioLabPlan(
      scenarioId: _scenarioId,
      executionBindingIds: <ScenarioExecutionBindingId>[_bindingId],
      controlIds: <ScenarioControlId>[_controlId],
      operationIds: <ScenarioLabOperationId>[
        ScenarioLabOperationId('assign-ready'),
      ],
      scriptIds: <ScenarioScriptId>[_scriptId],
      automatedAcceptanceCriterionIds: <AutomatedAcceptanceCriterionId>[
        AutomatedAcceptanceCriterionId('script-succeeded'),
        AutomatedAcceptanceCriterionId('feature-observed'),
      ],
      requiredEvidenceIds: const <RequiredEvidenceId>[],
      comparisonBindingIds: const <ScenarioComparisonBindingId>[],
      humanApprovalRequirementIds: const <HumanApprovalRequirementId>[],
      supplementalArtifactIds: const <SupplementalArtifactId>[],
    ),
  ],
);

File _writeTargetProcess(Directory workspace) {
  final script = File(p.join(workspace.path, 'lab_target.dart'));
  script.writeAsStringSync(r'''
import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final origin = Uri.parse('http://${server.address.address}:${server.port}');
  stdout.writeln(jsonEncode(TargetReadinessRecord(
    launchAttemptId: TargetLaunchAttemptId(
      Platform.environment['TARGET_LAUNCH_ATTEMPT_ID']!,
    ),
    targetId: Platform.environment['TARGET_ID']!,
    launchProfileId: Platform.environment['TARGET_LAUNCH_PROFILE_ID']!,
    origin: origin,
    processId: pid,
  ).toJson()));
  await for (final request in server) {
    if (request.uri.path == '/health') {
      request.response
        ..headers.contentType = ContentType.json
        ..write('{"status":"ready"}');
    } else {
      request.response.write('<!doctype html><title>Lab target</title>');
    }
    await request.response.close();
  }
}
''');
  return script;
}

Future<ScenarioLabRelayDescriptionV2> _waitForRelay(
  _RpcClient rpc,
  ScenarioLabRunId runId,
  Digest expectedStartRequestDigest,
) async {
  const timeout = Duration(seconds: 10);
  final stopwatch = Stopwatch()..start();
  ScenarioLabRelayDescriptionStatus? lastStatus;
  while (stopwatch.elapsed < timeout) {
    final response = await rpc.call(
      'lab.relay.v2.describe',
      ScenarioLabRelayDescribeRequestV2(
        runId: runId,
        expectedStartRequestDigest: expectedStartRequestDigest,
      ).toJson(),
    );
    expect(response.isSuccess, isTrue, reason: '${response.error}');
    final description = ScenarioLabRelayDescriptionV2.fromJson(response.result);
    lastStatus = description.status;
    if (description.status == ScenarioLabRelayDescriptionStatus.ready) {
      return description;
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  throw StateError(
    'Scenario Lab relay did not become ready within '
    '${timeout.inSeconds}s; last status: ${lastStatus?.name ?? 'none'}',
  );
}

Future<ScenarioLabRunObservation> _waitForTerminal(
  _RpcClient rpc,
  ScenarioLabRunId runId,
) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    final response = await rpc.call(
      'lab.reattach',
      ScenarioLabRunObserveRequest(runId: runId, afterSequence: -1).toJson(),
    );
    expect(response.isSuccess, isTrue, reason: '${response.error}');
    final observation = ScenarioLabRunObservation.fromJson(response.result);
    if (observation.disposition == ScenarioLabRunDisposition.terminal) {
      return observation;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('Scenario Lab run did not become terminal');
}

final class _RpcClient {
  _RpcClient(this.channel, this.iterator, this.sessionToken);

  final IOWebSocketChannel channel;
  final StreamIterator<Object?> iterator;
  final String sessionToken;
  var nextId = 1;

  static Future<_RpcClient> connect(
    HostRpcServer server,
    Uri studioOrigin,
  ) async {
    final channel = IOWebSocketChannel.connect(
      server.webSocketUri,
      headers: <String, String>{'Origin': studioOrigin.origin},
    );
    await channel.ready;
    return _RpcClient(
      channel,
      StreamIterator<Object?>(channel.stream),
      server.sessionToken,
    );
  }

  Future<JsonRpcResponse> initialize() => call(
    'workspace.initialize',
    <String, Object?>{'protocolVersion': 1, 'sessionToken': sessionToken},
  );

  Future<JsonRpcResponse> call(
    String method,
    Map<String, Object?> params,
  ) async {
    final id = 'request-${nextId++}';
    channel.sink.add(
      JsonRpcRequest(method: method, id: id, params: params).encode(),
    );
    while (await iterator.moveNext()) {
      final message = const JsonRpcCodec().decode(iterator.current! as String);
      if (message is JsonRpcResponse && message.id == id) return message;
    }
    throw StateError('RPC connection closed before response $id');
  }

  Future<void> close() async {
    await iterator.cancel();
    await channel.sink.close();
  }
}

String _repositoryRoot() {
  var current = Directory.current.absolute;
  while (true) {
    if (File(p.join(current.path, 'pubspec.yaml')).existsSync() &&
        Directory(p.join(current.path, 'libs')).existsSync()) {
      return current.path;
    }
    if (current.parent.path == current.path) {
      throw StateError('Repository root not found');
    }
    current = current.parent;
  }
}
