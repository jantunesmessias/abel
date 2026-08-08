import 'package:experience_contracts/experience_contracts.dart';

import '../ports.dart';

final class SessionCoordinator {
  SessionCoordinator({required this.clock, required this.ids});

  final Clock clock;
  final IdGenerator ids;
  final Map<String, _MutableSession> _sessions = <String, _MutableSession>{};

  SessionSnapshot create(LaunchProfile profile) {
    final now = clock.nowUtc();
    final session = _MutableSession(
      id: ids.nextId(),
      launchProfileId: profile.id,
      state: SessionState.created,
      createdAt: now,
      updatedAt: now,
    );
    _sessions[session.id] = session;
    _transition(session, SessionState.starting, 'session.starting');
    return session.snapshot();
  }

  SessionSnapshot markReady(String sessionId, ExecutionTarget target) {
    final session = _require(sessionId);
    _expect(session, const <SessionState>{SessionState.starting});
    session.target = target;
    _transition(session, SessionState.ready, 'session.ready', <String, Object?>{
      'targetId': target.id,
      'capabilities': <String>[
        for (final capability in target.capabilities) capability.id,
      ],
    });
    return session.snapshot();
  }

  SessionSnapshot requestReset(String sessionId) {
    final session = _require(sessionId);
    _expect(session, const <SessionState>{SessionState.ready});
    _transition(session, SessionState.resetting, 'session.reset.requested');
    return session.snapshot();
  }

  SessionSnapshot completeReset(String sessionId) {
    final session = _require(sessionId);
    _expect(session, const <SessionState>{SessionState.resetting});
    _transition(session, SessionState.ready, 'session.reset.completed');
    return session.snapshot();
  }

  SessionSnapshot requestStop(String sessionId) {
    final session = _require(sessionId);
    _expect(session, const <SessionState>{
      SessionState.starting,
      SessionState.ready,
      SessionState.resetting,
    });
    _transition(session, SessionState.stopping, 'session.stopping');
    return session.snapshot();
  }

  SessionSnapshot completeStop(String sessionId) => _terminal(
    sessionId,
    SessionState.stopped,
    'session.stopped',
    'stopped',
    allowed: const <SessionState>{SessionState.stopping},
  );

  SessionSnapshot cancel(String sessionId, String reason) => _terminal(
    sessionId,
    SessionState.cancelled,
    'session.cancelled',
    reason,
    allowed: const <SessionState>{
      SessionState.created,
      SessionState.starting,
      SessionState.ready,
      SessionState.resetting,
      SessionState.stopping,
    },
  );

  SessionSnapshot fail(String sessionId, String reason) => _terminal(
    sessionId,
    SessionState.failed,
    'session.failed',
    reason,
    allowed: const <SessionState>{
      SessionState.created,
      SessionState.starting,
      SessionState.ready,
      SessionState.resetting,
      SessionState.stopping,
    },
  );

  CaptureRequest requestCapture(String sessionId, {String format = 'png'}) {
    final session = _require(sessionId);
    _expect(session, const <SessionState>{SessionState.ready});
    final request = CaptureRequest(
      id: ids.nextId(),
      sessionId: sessionId,
      format: format,
    );
    _trace(session, 'capture.requested', <String, Object?>{
      'captureRequestId': request.id,
      'format': format,
    });
    return request;
  }

  SessionSnapshot snapshot(String sessionId) => _require(sessionId).snapshot();

  List<SessionSnapshot> get activeSessions => _sessions.values
      .where((session) => !session.state.isTerminal)
      .map((session) => session.snapshot())
      .toList(growable: false);

  SessionSnapshot _terminal(
    String sessionId,
    SessionState state,
    String event,
    String reason, {
    required Set<SessionState> allowed,
  }) {
    final session = _require(sessionId);
    _expect(session, allowed);
    session.terminalReason = reason;
    _transition(session, state, event, <String, Object?>{'reason': reason});
    return session.snapshot();
  }

  _MutableSession _require(String id) {
    final session = _sessions[id];
    if (session == null) throw StateError('Unknown session $id');
    return session;
  }

  void _expect(_MutableSession session, Set<SessionState> allowed) {
    if (session.state.isTerminal) {
      throw StateError('Session ${session.id} already has a terminal result');
    }
    if (!allowed.contains(session.state)) {
      throw StateError('Invalid transition from ${session.state.name}');
    }
  }

  void _transition(
    _MutableSession session,
    SessionState state,
    String event, [
    Map<String, Object?> data = const <String, Object?>{},
  ]) {
    session.state = state;
    _trace(session, event, data);
  }

  void _trace(
    _MutableSession session,
    String event,
    Map<String, Object?> data,
  ) {
    final now = clock.nowUtc();
    session.updatedAt = now;
    session.trace.add(
      SessionTraceEntry(
        sequence: session.trace.length + 1,
        recordedAt: now,
        event: event,
        data: data,
      ),
    );
  }
}

final class _MutableSession {
  _MutableSession({
    required this.id,
    required this.launchProfileId,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String launchProfileId;
  SessionState state;
  final DateTime createdAt;
  DateTime updatedAt;
  final List<SessionTraceEntry> trace = <SessionTraceEntry>[];
  ExecutionTarget? target;
  String? terminalReason;

  SessionSnapshot snapshot() => SessionSnapshot(
    id: id,
    launchProfileId: launchProfileId,
    state: state,
    createdAt: createdAt,
    updatedAt: updatedAt,
    trace: trace,
    target: target,
    terminalReason: terminalReason,
  );
}
