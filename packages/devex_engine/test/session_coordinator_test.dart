import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';
import 'package:test/test.dart';

void main() {
  late _Clock clock;
  late SessionCoordinator coordinator;

  setUp(() {
    clock = _Clock();
    coordinator = SessionCoordinator(clock: clock, ids: _Ids());
  });

  test('runs start, ready, reset, capture, and one terminal result', () {
    final starting = coordinator.create(_profile());
    expect(starting.state, SessionState.starting);

    clock.advance();
    final ready = coordinator.markReady(starting.id, _target());
    expect(ready.state, SessionState.ready);
    final resetting = coordinator.requestReset(starting.id);
    expect(resetting.state, SessionState.resetting);
    expect(coordinator.completeReset(starting.id).state, SessionState.ready);
    final capture = coordinator.requestCapture(starting.id);
    expect(capture.sessionId, starting.id);
    coordinator.requestStop(starting.id);
    final stopped = coordinator.completeStop(starting.id);

    expect(stopped.state, SessionState.stopped);
    expect(
      stopped.trace.map((entry) => entry.sequence),
      orderedEquals(<int>[1, 2, 3, 4, 5, 6, 7]),
    );
    expect(() => coordinator.cancel(starting.id, 'late'), throwsStateError);
    expect(coordinator.activeSessions, isEmpty);
  });

  test('cancellation is terminal from startup', () {
    final session = coordinator.create(_profile());
    final cancelled = coordinator.cancel(session.id, 'user');

    expect(cancelled.state, SessionState.cancelled);
    expect(cancelled.terminalReason, 'user');
    expect(
      () => coordinator.markReady(session.id, _target()),
      throwsStateError,
    );
  });
}

LaunchProfile _profile() => LaunchProfile(
  id: 'web-default',
  applicationId: ApplicationId('app'),
  platform: TargetPlatform.web,
  command: 'flutter',
  arguments: const <String>['run', '-d', 'web-server'],
  workingDirectory: '.',
  overlay: RuntimeConfigurationOverlay(const <String, String>{}),
  bootstrapPolicy: ApplicationBootstrapPolicy(
    const <String, BootstrapDependencyPolicy>{},
  ),
);

ExecutionTarget _target() => ExecutionTarget(
  id: 'target-1',
  platform: TargetPlatform.web,
  origin: Uri.parse('http://127.0.0.1:8123'),
  capabilities: <CapabilityDescriptor>[
    CapabilityDescriptor(
      id: 'sample.simulated-theme',
      version: 1,
      operations: const <String>{'set', 'reset'},
    ),
  ],
);

final class _Clock implements Clock {
  var current = DateTime.utc(2026, 8, 9);
  var ticks = 0;

  void advance() {
    current = current.add(const Duration(seconds: 1));
    ticks += 1000000;
  }

  @override
  int monotonicMicroseconds() => ticks;

  @override
  DateTime nowUtc() => current;
}

final class _Ids implements IdGenerator {
  var next = 1;

  @override
  String nextId() => 'id-${next++}';
}
