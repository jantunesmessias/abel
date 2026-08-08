import 'dart:async';
import 'dart:convert';

import 'package:execution_runtime/src/gateway/gateway_sidecar_supervisor.dart';
import 'package:execution_runtime/src/lab/managed_process_scenario_lab_target.dart';
import 'package:execution_runtime/src/lab/scenario_lab_execution_ports.dart';
import 'package:execution_runtime/src/lab/scenario_lab_relay_broker.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:test/test.dart';

void main() {
  test('waits for Hello and dispatches one request/response command', () async {
    final fixture = _Fixture(origin: Uri.parse('http://127.0.0.1:9191'));
    addTearDown(fixture.close);

    final runtimeInputs = fixture.adapter.resolveRuntimeInputs(
      runId: _runId,
      binding: _binding,
    );
    expect(runtimeInputs.executionTargetId, _binding.targetId);

    final attached = fixture.adapter.attach(
      runId: _runId,
      binding: _binding,
      nonce: _nonce,
      cancellation: fixture.cancellation,
    );
    final descriptor = await fixture.waitForDescriptor();
    expect(descriptor.origin, Uri.parse('http://127.0.0.1:9191'));
    expect(descriptor.origin, fixture.launcher.lastHandle!.readiness.origin);
    expect(
      descriptor.launchAttemptId,
      fixture.launcher.lastLaunch!.launchAttemptId,
    );
    expect(
      fixture.adapter.launchContext(_runId)!.targetOrigin,
      descriptor.origin,
    );
    expect(
      fixture.adapter.launchContext(_runId)!.executionFingerprint.digest,
      runtimeInputs.executionFingerprintDigest,
    );

    final hello = _hello();
    fixture.broker.acceptHello(hello);
    final session = await attached;
    expect(session.hello.digest, hello.digest);

    final polled = fixture.broker.nextCommand(_runId, afterSequence: 0);
    final command = _readCommand();
    final executed = session.execute(
      command,
      cancellation: fixture.cancellation,
    );
    expect((await polled)!.commandDigest, command.commandDigest);
    final result = _readResult(command);
    fixture.broker.acceptResult(result);
    expect((await executed).resultDigest, result.resultDigest);

    await session.close();
    expect(fixture.broker.describe(_runId), isNull);
    expect(fixture.launcher.lastHandle!.stopCalls, 1);
    expect(fixture.gateway.startCalls, isEmpty);
    expect(fixture.adapter.launchContext(_runId), isNull);
  });

  test(
    'starts Gateway from validated readiness and retains only internal origin',
    () async {
      final targetOrigin = Uri.parse('http://127.0.0.1:9292');
      final fixture = _Fixture(withGateway: true, origin: targetOrigin);
      addTearDown(fixture.close);

      final attached = fixture.adapter.attach(
        runId: _runId,
        binding: fixture.binding,
        nonce: _nonce,
        cancellation: fixture.cancellation,
      );
      final descriptor = await fixture.waitForDescriptor();

      expect(fixture.gateway.startCalls, hasLength(1));
      expect(fixture.gateway.startCalls.single.targetOrigin, targetOrigin);
      expect(
        fixture.gateway.startCalls.single.plan.digest,
        fixture.configuration.gatewayPlan!.digest,
      );
      expect(descriptor.origin, targetOrigin);
      expect(
        fixture.adapter.launchContext(_runId)!.gatewayDataOrigin,
        fixture.gateway.dataOrigin,
      );
      expect(
        fixture.adapter.launchContext(_runId)!.executionFingerprint.digest,
        fixture.configuration.runtimeInputs.executionFingerprintDigest,
      );
      expect(fixture.adapter.activeGatewayCount, 1);

      fixture.broker.acceptHello(_hello());
      final session = await attached;
      await session.close();

      expect(fixture.gateway.activeOwners, isEmpty);
      expect(fixture.adapter.activeGatewayCount, 0);
      expect(fixture.adapter.launchContext(_runId), isNull);
      expect(fixture.launcher.lastHandle!.stopCalls, 1);
    },
  );

  test('required Gateway fails before reserving a process', () async {
    final fixture = _Fixture(withGateway: true, gatewayAvailable: false);
    addTearDown(fixture.close);

    expect(
      () => fixture.adapter.resolveRuntimeInputs(
        runId: _runId,
        binding: fixture.binding,
      ),
      throwsUnsupportedError,
    );
    await expectLater(
      fixture.adapter.attach(
        runId: _runId,
        binding: fixture.binding,
        nonce: _nonce,
        cancellation: fixture.cancellation,
      ),
      throwsUnsupportedError,
    );

    expect(fixture.launcher.lastLaunch, isNull);
    expect(fixture.gateway.startCalls, isEmpty);
    expect(fixture.adapter.activeProcessCount, 0);
  });

  test('fingerprint mismatch is rejected before reserving a process', () {
    final fixture = _Fixture(fingerprintMismatch: true);
    addTearDown(fixture.close);

    expect(
      () => fixture.adapter.resolveRuntimeInputs(
        runId: _runId,
        binding: fixture.binding,
      ),
      throwsArgumentError,
    );
    expect(fixture.launcher.lastLaunch, isNull);
  });

  test('partial Gateway start failure stops its owner and process', () async {
    final fixture = _Fixture(withGateway: true, gatewayStartFails: true);
    addTearDown(fixture.close);

    await expectLater(
      fixture.adapter.attach(
        runId: _runId,
        binding: fixture.binding,
        nonce: _nonce,
        cancellation: fixture.cancellation,
      ),
      throwsStateError,
    );

    expect(fixture.gateway.startCalls, hasLength(1));
    expect(fixture.gateway.activeOwners, isEmpty);
    expect(fixture.gateway.stopOwnerCalls, 1);
    expect(fixture.launcher.lastHandle!.stopCalls, 1);
    expect(fixture.broker.describe(_runId), isNull);
  });

  test('mismatched Gateway readiness is rejected and cleaned up', () async {
    final fixture = _Fixture(withGateway: true, gatewayDigestMismatch: true);
    addTearDown(fixture.close);

    await expectLater(
      fixture.adapter.attach(
        runId: _runId,
        binding: fixture.binding,
        nonce: _nonce,
        cancellation: fixture.cancellation,
      ),
      throwsFormatException,
    );

    expect(fixture.gateway.activeOwners, isEmpty);
    expect(fixture.launcher.lastHandle!.stopCalls, 1);
    expect(fixture.broker.describe(_runId), isNull);
  });

  test('unsafe Gateway data origin is rejected and cleaned up', () async {
    final fixture = _Fixture(
      withGateway: true,
      gatewayDataOrigin: Uri.parse('http://127.0.0.1:9393?token=secret'),
    );
    addTearDown(fixture.close);

    await expectLater(
      fixture.adapter.attach(
        runId: _runId,
        binding: fixture.binding,
        nonce: _nonce,
        cancellation: fixture.cancellation,
      ),
      throwsFormatException,
    );

    expect(fixture.gateway.activeOwners, isEmpty);
    expect(fixture.gateway.stopOwnerCalls, 1);
    expect(fixture.launcher.lastHandle!.stopCalls, 1);
    expect(fixture.adapter.activeGatewayCount, 0);
    expect(fixture.broker.describe(_runId), isNull);
  });

  test(
    'run abort drains a late process launch without creating a session',
    () async {
      final launchGate = Completer<void>();
      final fixture = _Fixture(launchGate: launchGate);
      addTearDown(fixture.close);

      final attached = fixture.adapter.attach(
        runId: _runId,
        binding: fixture.binding,
        nonce: _nonce,
        cancellation: fixture.cancellation,
      );
      await fixture.waitForLaunch();

      final aborted = fixture.adapter.abort(_runId);
      await fixture.waitForLauncherAbort();
      launchGate.complete();

      await expectLater(attached, throwsA(isA<ScenarioLabTargetCancelled>()));
      await aborted;
      expect(fixture.launcher.lastHandle!.stopCalls, 1);
      expect(fixture.adapter.activeProcessCount, 0);
      expect(fixture.adapter.activeSessionCount, 0);
      expect(fixture.adapter.launchContext(_runId), isNull);
      expect(fixture.broker.describe(_runId), isNull);
    },
  );

  test(
    'run abort interrupts pending Gateway startup and drains owner',
    () async {
      final startGate = Completer<void>();
      final fixture = _Fixture(withGateway: true, gatewayStartGate: startGate);
      addTearDown(fixture.close);

      final attached = fixture.adapter.attach(
        runId: _runId,
        binding: fixture.binding,
        nonce: _nonce,
        cancellation: fixture.cancellation,
      );
      await fixture.waitForGatewayStart();

      final aborted = fixture.adapter.abort(_runId);
      await fixture.waitForGatewayStop();
      startGate.complete();

      await expectLater(attached, throwsA(isA<ScenarioLabTargetCancelled>()));
      await aborted;
      expect(fixture.gateway.activeOwners, isEmpty);
      expect(fixture.launcher.lastHandle!.stopCalls, 1);
      expect(fixture.adapter.activeGatewayCount, 0);
      expect(fixture.adapter.activeProcessCount, 0);
      expect(fixture.broker.describe(_runId), isNull);
    },
  );

  test('Hello timeout closes both relay and managed process', () async {
    final fixture = _Fixture(
      withGateway: true,
      helloTimeout: const Duration(milliseconds: 10),
    );
    addTearDown(fixture.close);

    final attached = fixture.adapter.attach(
      runId: _runId,
      binding: fixture.binding,
      nonce: _nonce,
      cancellation: fixture.cancellation,
    );
    await fixture.waitForDescriptor();

    await expectLater(attached, throwsA(isA<TimeoutException>()));
    expect(fixture.broker.describe(_runId), isNull);
    expect(fixture.launcher.lastHandle!.stopCalls, 1);
    expect(fixture.gateway.activeOwners, isEmpty);
    expect(fixture.adapter.activeGatewayCount, 0);
  });

  test('cancellation before Hello closes relay and process', () async {
    final fixture = _Fixture(withGateway: true);
    addTearDown(fixture.close);

    final attached = fixture.adapter.attach(
      runId: _runId,
      binding: fixture.binding,
      nonce: _nonce,
      cancellation: fixture.cancellation,
    );
    await fixture.waitForDescriptor();
    fixture.cancellation.cancel();

    await expectLater(attached, throwsA(isA<ScenarioLabTargetCancelled>()));
    expect(fixture.broker.describe(_runId), isNull);
    expect(fixture.launcher.lastHandle!.stopCalls, 1);
    expect(fixture.gateway.activeOwners, isEmpty);
  });

  test('run abort reports an incomplete process cleanup', () async {
    final fixture = _Fixture(processStopFails: true);
    addTearDown(fixture.close);

    final attached = fixture.adapter.attach(
      runId: _runId,
      binding: fixture.binding,
      nonce: _nonce,
      cancellation: fixture.cancellation,
    );
    await fixture.waitForDescriptor();
    final attachFailure = expectLater(attached, throwsStateError);

    await expectLater(fixture.adapter.abort(_runId), throwsStateError);
    await attachFailure;

    expect(fixture.launcher.lastHandle!.stopCalls, 1);
    expect(fixture.adapter.activeProcessCount, 0);
    expect(fixture.adapter.activeSessionCount, 0);
    expect(fixture.broker.describe(_runId), isNull);
  });

  test('process exit before Hello stops Gateway and rejects attach', () async {
    final fixture = _Fixture(withGateway: true);
    addTearDown(fixture.close);

    final attached = fixture.adapter.attach(
      runId: _runId,
      binding: fixture.binding,
      nonce: _nonce,
      cancellation: fixture.cancellation,
    );
    await fixture.waitForDescriptor();
    fixture.launcher.lastHandle!.exit(17);

    await expectLater(attached, throwsA(isA<ScenarioLabAdapterDisconnected>()));
    expect(fixture.gateway.activeOwners, isEmpty);
    expect(fixture.adapter.activeGatewayCount, 0);
    expect(fixture.broker.describe(_runId), isNull);
    expect(fixture.launcher.lastHandle!.stopCalls, 1);
  });

  test('process exit closes relay and disconnects pending dispatch', () async {
    final fixture = _Fixture(withGateway: true);
    addTearDown(fixture.close);

    final attached = fixture.adapter.attach(
      runId: _runId,
      binding: fixture.binding,
      nonce: _nonce,
      cancellation: fixture.cancellation,
    );
    await fixture.waitForDescriptor();
    fixture.broker.acceptHello(_hello());
    final session = await attached;
    final command = _readCommand();
    final executed = session.execute(
      command,
      cancellation: fixture.cancellation,
    );
    await fixture.broker.nextCommand(
      _runId,
      afterSequence: 0,
      wait: Duration.zero,
    );

    fixture.launcher.lastHandle!.exit(17);

    await expectLater(executed, throwsA(isA<ScenarioLabAdapterDisconnected>()));
    expect(fixture.broker.describe(_runId), isNull);
    await fixture.waitForNoGateway();
    expect(fixture.gateway.activeOwners, isEmpty);
    expect(fixture.adapter.activeGatewayCount, 0);
    await session.close();
    expect(fixture.launcher.lastHandle!.stopCalls, 1);
  });

  test('rejects fake readiness not bound to the Host launch attempt', () async {
    final fixture = _Fixture(
      withGateway: true,
      readinessAttempt: TargetLaunchAttemptId('different-attempt-000001'),
    );
    addTearDown(fixture.close);

    await expectLater(
      fixture.adapter.attach(
        runId: _runId,
        binding: fixture.binding,
        nonce: _nonce,
        cancellation: fixture.cancellation,
      ),
      throwsFormatException,
    );

    expect(fixture.broker.describe(_runId), isNull);
    expect(fixture.launcher.lastHandle!.stopCalls, 1);
    expect(fixture.gateway.startCalls, isEmpty);
  });

  test(
    'port close waits for pending Gateway startup and leaves no owner',
    () async {
      final startGate = Completer<void>();
      final fixture = _Fixture(withGateway: true, gatewayStartGate: startGate);

      final attached = fixture.adapter.attach(
        runId: _runId,
        binding: fixture.binding,
        nonce: _nonce,
        cancellation: fixture.cancellation,
      );
      await fixture.waitForGatewayStart();
      final closed = fixture.adapter.close();
      await Future<void>.delayed(Duration.zero);
      expect(fixture.gateway.activeOwners, isEmpty);

      startGate.complete();
      await expectLater(attached, throwsA(isA<ScenarioLabTargetCancelled>()));
      await closed;

      expect(fixture.gateway.activeOwners, isEmpty);
      expect(fixture.adapter.activeGatewayCount, 0);
      expect(fixture.adapter.activeProcessCount, 0);
      expect(fixture.launcher.lastHandle!.stopCalls, 1);
    },
  );

  test('relay origin has no caller-controlled input path', () async {
    final readinessOrigin = Uri.parse('http://localhost:8484');
    final fixture = _Fixture(origin: readinessOrigin);
    addTearDown(fixture.close);

    final attached = fixture.adapter.attach(
      runId: _runId,
      binding: _binding,
      nonce: _nonce,
      cancellation: fixture.cancellation,
    );
    final descriptor = await fixture.waitForDescriptor();

    expect(descriptor.origin, readinessOrigin);
    expect(fixture.configuration.launchProfile.id, _binding.launchProfileId);
    fixture.broker.acceptHello(_hello());
    await (await attached).close();
  });
}

final _runId = ScenarioLabRunId('run-00000001');
final _nonce = AppAdapterRelayNonce('relay-nonce-000000000001');
final _capability = AppAdapterCapabilityReference(
  id: AppAdapterCapabilityId('sample.ready-control'),
  version: 1,
);
final _binding = ScenarioExecutionBinding(
  id: ScenarioExecutionBindingId('dashboard-ready-web'),
  scenarioId: ScenarioId('dashboard-ready'),
  targetId: 'sample-target',
  launchProfileId: 'sample-web',
);
final _gatewayBinding = ScenarioExecutionBinding(
  id: ScenarioExecutionBindingId('dashboard-ready-web-gateway'),
  scenarioId: ScenarioId('dashboard-ready'),
  targetId: 'sample-target',
  launchProfileId: 'sample-web',
  gatewayPresetId: 'delivery-ready',
);

final class _Fixture {
  _Fixture({
    Uri? origin,
    bool withGateway = false,
    bool gatewayAvailable = true,
    bool gatewayStartFails = false,
    bool gatewayDigestMismatch = false,
    bool fingerprintMismatch = false,
    bool processStopFails = false,
    Completer<void>? launchGate,
    Completer<void>? gatewayStartGate,
    Uri? gatewayDataOrigin,
    TargetLaunchAttemptId? readinessAttempt,
    Duration helloTimeout = const Duration(seconds: 5),
  }) : launcher = _FakeLauncher(
         origin: origin ?? Uri.parse('http://127.0.0.1:8181'),
         readinessAttempt: readinessAttempt,
         launchGate: launchGate,
         processStopFails: processStopFails,
       ) {
    binding = withGateway ? _gatewayBinding : _binding;
    final gatewayCompilation = _gatewayCompilation();
    gateway = _FakeGatewayLifecycle(
      routingTableDigest: gatewayCompilation.routingTable.digest,
      failAfterReservation: gatewayStartFails,
      digestMismatch: gatewayDigestMismatch,
      startGate: gatewayStartGate,
      dataOrigin: gatewayDataOrigin ?? Uri.parse('http://127.0.0.1:9393'),
    );
    final launchProfile = LaunchProfile(
      id: 'sample-web',
      applicationId: ApplicationId('sample'),
      platform: TargetPlatform.web,
      command: 'dart',
      arguments: const <String>['run', 'target.dart'],
      workingDirectory: '.',
      overlay: RuntimeConfigurationOverlay(const <String, String>{}),
      bootstrapPolicy: ApplicationBootstrapPolicy(
        const <String, BootstrapDependencyPolicy>{},
      ),
    );
    final executionFingerprint = ExecutionFingerprint(
      catalogDigest: Digest.semantic('catalog'),
      launchProfileId: launchProfile.id,
      targetId: binding.targetId,
      platform: launchProfile.platform.name,
      renderer: 'flutter-web',
      runtimeFidelity: RuntimeFidelity.simulated,
      backendMode: withGateway
          ? gatewayCompilation.plan.backendMode
          : BackendMode.none,
      networkContainment: withGateway
          ? gatewayCompilation.plan.networkContainment
          : NetworkContainment.unconstrained,
      bootstrapAssessment: BootstrapAssessment.declared,
      toolchain: const <String, String>{'dart': 'test'},
      capabilities: const <String>{'app-adapter.relay'},
    );
    configuration = ScenarioLabManagedTargetConfiguration(
      launchProfile: launchProfile,
      executionFingerprint: executionFingerprint,
      runtimeInputs: ScenarioLabRuntimeInputBinding(
        executionFingerprintDigest: fingerprintMismatch
            ? Digest.semantic('another-fingerprint')
            : executionFingerprint.digest,
        executionTargetId: binding.targetId,
        gatewayPresetId: withGateway ? gatewayCompilation.plan.preset.id : null,
        compiledGatewayPlanDigest: withGateway
            ? gatewayCompilation.plan.digest
            : null,
        routingTableDigest: withGateway
            ? gatewayCompilation.routingTable.digest
            : null,
      ),
      gatewayPlan: withGateway ? gatewayCompilation.plan : null,
    );
    adapter = ManagedProcessScenarioLabTargetPort(
      launcher: launcher,
      broker: broker,
      gateway: gatewayAvailable ? gateway : null,
      resolveConfiguration: (runId, binding) => configuration,
      ids: _FixedIds(),
      helloTimeout: helloTimeout,
    );
  }

  final ScenarioLabRelayBroker broker = ScenarioLabRelayBroker();
  final _Cancellation cancellation = _Cancellation();
  final _FakeLauncher launcher;
  late final ScenarioExecutionBinding binding;
  late final _FakeGatewayLifecycle gateway;
  late final ScenarioLabManagedTargetConfiguration configuration;
  late final ManagedProcessScenarioLabTargetPort adapter;

  Future<ScenarioLabRelayTargetDescriptor> waitForDescriptor() async {
    for (var attempt = 0; attempt < 100; attempt += 1) {
      final descriptor = broker.describe(_runId);
      if (descriptor != null) return descriptor;
      await Future<void>.delayed(Duration.zero);
    }
    throw StateError('Relay descriptor was not opened');
  }

  Future<void> waitForGatewayStart() async {
    for (var attempt = 0; attempt < 100; attempt += 1) {
      if (gateway.startCalls.isNotEmpty) return;
      await Future<void>.delayed(Duration.zero);
    }
    throw StateError('Gateway startup was not requested');
  }

  Future<void> waitForLaunch() async {
    for (var attempt = 0; attempt < 100; attempt += 1) {
      if (launcher.lastLaunch != null) return;
      await Future<void>.delayed(Duration.zero);
    }
    throw StateError('Target launch was not requested');
  }

  Future<void> waitForLauncherAbort() async {
    for (var attempt = 0; attempt < 100; attempt += 1) {
      if (launcher.abortCalls > 0) return;
      await Future<void>.delayed(Duration.zero);
    }
    throw StateError('Target launch was not aborted');
  }

  Future<void> waitForGatewayStop() async {
    for (var attempt = 0; attempt < 100; attempt += 1) {
      if (gateway.stopOwnerCalls > 0 && gateway.activeOwners.isEmpty) return;
      await Future<void>.delayed(Duration.zero);
    }
    throw StateError('Gateway owner was not stopped');
  }

  Future<void> waitForNoGateway() async {
    for (var attempt = 0; attempt < 100; attempt += 1) {
      if (gateway.activeOwners.isEmpty && adapter.activeGatewayCount == 0) {
        return;
      }
      await Future<void>.delayed(Duration.zero);
    }
    throw StateError('Gateway owner remained active');
  }

  Future<void> close() => adapter.close();
}

final class _FixedIds implements IdGenerator {
  @override
  String nextId() => 'launch-attempt-00000001';
}

final class _Cancellation implements ScenarioLabCancellationSignal {
  final Completer<void> _cancelled = Completer<void>();

  @override
  bool get isCancelled => _cancelled.isCompleted;

  @override
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

final class _FakeLauncher implements ScenarioLabManagedProcessLauncher {
  _FakeLauncher({
    required this.origin,
    this.readinessAttempt,
    this.launchGate,
    this.processStopFails = false,
  });

  final Uri origin;
  final TargetLaunchAttemptId? readinessAttempt;
  final Completer<void>? launchGate;
  final bool processStopFails;
  _LaunchCall? lastLaunch;
  _FakeProcessHandle? lastHandle;
  var closeCalls = 0;
  var abortCalls = 0;

  @override
  Future<ScenarioLabManagedProcessHandle> launch({
    required String ownerId,
    required LaunchProfile profile,
    required String targetId,
    required TargetLaunchAttemptId launchAttemptId,
    required Duration timeout,
  }) async {
    lastLaunch = _LaunchCall(
      ownerId: ownerId,
      profile: profile,
      targetId: targetId,
      launchAttemptId: launchAttemptId,
      timeout: timeout,
    );
    final handle = lastHandle = _FakeProcessHandle(
      readiness: TargetReadinessRecord(
        launchAttemptId: readinessAttempt ?? launchAttemptId,
        targetId: targetId,
        launchProfileId: profile.id,
        origin: origin,
        processId: 4242,
      ),
      ownerId: ownerId,
      stopFails: processStopFails,
    );
    if (launchGate != null) await launchGate!.future;
    return handle;
  }

  @override
  Future<void> abort(String ownerId) async {
    abortCalls += 1;
  }

  @override
  Future<void> close() async {
    closeCalls += 1;
  }
}

final class _FakeGatewayLifecycle implements ScenarioLabGatewayLifecyclePort {
  _FakeGatewayLifecycle({
    required this.routingTableDigest,
    required this.failAfterReservation,
    required this.digestMismatch,
    required this.startGate,
    required this.dataOrigin,
  });

  final Digest routingTableDigest;
  final bool failAfterReservation;
  final bool digestMismatch;
  final Completer<void>? startGate;
  final Uri dataOrigin;
  final List<_GatewayStartCall> startCalls = <_GatewayStartCall>[];
  final Set<String> activeOwners = <String>{};
  var stopOwnerCalls = 0;

  @override
  Future<GatewaySidecarHandle> start({
    required String ownerSessionId,
    required Uri targetOrigin,
    required CompiledGatewayPlan plan,
  }) async {
    startCalls.add(
      _GatewayStartCall(
        ownerSessionId: ownerSessionId,
        targetOrigin: targetOrigin,
        plan: plan,
      ),
    );
    activeOwners.add(ownerSessionId);
    if (startGate != null) await startGate!.future;
    if (!activeOwners.contains(ownerSessionId)) {
      throw StateError('Gateway owner stopped during startup');
    }
    if (failAfterReservation) {
      throw StateError('Gateway startup failed after reservation');
    }
    return GatewaySidecarHandle(
      id: 'gateway-test-000001',
      ownerSessionId: ownerSessionId,
      dataOrigin: dataOrigin,
      planDigest: plan.digest,
      routingTableDigest: digestMismatch
          ? Digest.semantic('another-routing-table')
          : routingTableDigest,
    );
  }

  @override
  Future<void> stopOwner(String ownerSessionId) async {
    stopOwnerCalls += 1;
    activeOwners.remove(ownerSessionId);
  }
}

final class _GatewayStartCall {
  const _GatewayStartCall({
    required this.ownerSessionId,
    required this.targetOrigin,
    required this.plan,
  });

  final String ownerSessionId;
  final Uri targetOrigin;
  final CompiledGatewayPlan plan;
}

final class _LaunchCall {
  const _LaunchCall({
    required this.ownerId,
    required this.profile,
    required this.targetId,
    required this.launchAttemptId,
    required this.timeout,
  });

  final String ownerId;
  final LaunchProfile profile;
  final String targetId;
  final TargetLaunchAttemptId launchAttemptId;
  final Duration timeout;
}

final class _FakeProcessHandle implements ScenarioLabManagedProcessHandle {
  _FakeProcessHandle({
    required this.readiness,
    required this.ownerId,
    this.stopFails = false,
  });

  final String ownerId;
  final bool stopFails;

  @override
  final TargetReadinessRecord readiness;

  final Completer<ScenarioLabManagedProcessExit> _exited =
      Completer<ScenarioLabManagedProcessExit>();
  var stopCalls = 0;
  var _stopped = false;

  @override
  Future<ScenarioLabManagedProcessExit> get exited => _exited.future;

  void exit(int exitCode) {
    if (!_exited.isCompleted) {
      _exited.complete(
        ScenarioLabManagedProcessExit(
          ownerId: ownerId,
          exitCode: exitCode,
          stdoutTail: '',
          stderrTail: '',
        ),
      );
    }
  }

  @override
  Future<void> stop() async {
    if (_stopped) return;
    stopCalls += 1;
    if (stopFails) throw StateError('Managed process stop failed');
    _stopped = true;
    exit(-15);
  }
}

GatewayCompilation _gatewayCompilation() {
  final scopeId = GatewayScopeId('delivery');
  final presetId = GatewayPresetId('delivery-ready');
  final routeId = GatewayRouteId('dashboard');
  final fixtureId = GatewayFixtureId('dashboard-ready');
  final fixtureBytes = utf8.encode('{"state":"ready"}');
  return const GatewayPlanCompiler().compile(
    scope: GatewayScope(
      id: scopeId,
      displayName: 'Delivery',
      routeIds: <GatewayRouteId>[routeId],
    ),
    preset: GatewayPreset(
      id: presetId,
      scopeId: scopeId,
      description: 'Delivery ready',
      routeIds: <GatewayRouteId>[routeId],
    ),
    routes: <GatewayRoute>[
      GatewayRoute(
        id: routeId,
        scopeId: scopeId,
        method: 'GET',
        pathTemplate: '/dashboard',
        requiredQuery: const <String, String>{},
        appliesTo: <GatewayPresetId>{presetId},
        policy: GatewayRoutePolicy.localOnly,
        fixtureId: fixtureId,
      ),
    ],
    fixtures: <GatewayFixture>[
      GatewayFixture(
        id: fixtureId,
        status: 200,
        headers: const <String, String>{'content-type': 'application/json'},
        bodyDigest: Digest.bytes(fixtureBytes),
        bodySize: fixtureBytes.length,
        mediaType: 'application/json',
      ),
    ],
  );
}

AppAdapterRelayHello _hello() => AppAdapterRelayHello(
  runId: _runId,
  adapterInstanceId: 'adapter-instance-1',
  sequence: 0,
  nonce: _nonce,
  capabilities: <AppAdapterCapabilityReference>[_capability],
);

ReadAppAdapterRelayCommand _readCommand() => ReadAppAdapterRelayCommand(
  runId: _runId,
  commandId: ScenarioLabCommandId('command-00000001'),
  sequence: 1,
  nonce: _nonce,
  controlId: ScenarioControlId('ready-control'),
  capability: _capability,
  operationId: CapabilityOperationId('read'),
);

ReadAppAdapterRelayResult _readResult(ReadAppAdapterRelayCommand command) =>
    ReadAppAdapterRelayResult(
      runId: command.runId,
      commandId: command.commandId,
      sequence: command.sequence,
      nonce: command.nonce,
      state: AppAdapterRelayResultState.succeeded,
      value: const BooleanScenarioControlValue(true),
    );
