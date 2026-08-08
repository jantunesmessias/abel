import 'dart:async';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';

final class InMemoryHostedCollaborationRepository
    implements HostedCollaborationRepository {
  final Map<String, _TenantState> _tenants = <String, _TenantState>{};
  Future<void> _transactionTail = Future<void>.value();

  void seedMembership(Membership membership) {
    final state = _tenants.putIfAbsent(membership.tenantId, _TenantState.new);
    state.roles[membership.principalId] = membership.role;
  }

  void seedWorkspaceHead({
    required String tenantId,
    required String workspaceId,
    required Digest digest,
  }) {
    _tenants.putIfAbsent(tenantId, _TenantState.new).heads[workspaceId] =
        digest;
  }

  Digest? workspaceHead(String tenantId, String workspaceId) =>
      _tenants[tenantId]?.heads[workspaceId];

  List<AuditEvent> auditForTenant(String tenantId) =>
      List<AuditEvent>.unmodifiable(_tenants[tenantId]?.audit ?? const []);

  @override
  Future<T> inTenantTransaction<T>(
    HostedRequestContext context,
    Future<T> Function(HostedCollaborationTransaction transaction) operation,
  ) async {
    final previous = _transactionTail;
    final release = Completer<void>();
    _transactionTail = release.future;
    await previous;
    try {
      final working = (_tenants[context.tenantId] ?? _TenantState()).copy();
      final result = await operation(
        _InMemoryHostedTransaction(context, working),
      );
      _tenants[context.tenantId] = working;
      return result;
    } finally {
      release.complete();
    }
  }
}

final class _TenantState {
  _TenantState();

  final Map<String, MembershipRole> roles = <String, MembershipRole>{};
  final Map<String, Digest> heads = <String, Digest>{};
  final Map<Digest, WorkspaceRevision> revisions =
      <Digest, WorkspaceRevision>{};
  final Map<String, List<CollaborationEvent>> events =
      <String, List<CollaborationEvent>>{};
  final Map<String, PresenceLease> presence = <String, PresenceLease>{};
  final Map<String, CommentThread> comments = <String, CommentThread>{};
  final List<Approval> approvals = <Approval>[];
  final Map<Digest, Release> releases = <Digest, Release>{};
  final List<AuditEvent> audit = <AuditEvent>[];
  final Map<String, _StoredPush> pushes = <String, _StoredPush>{};

  _TenantState copy() {
    final result = _TenantState();
    result.roles.addAll(roles);
    result.heads.addAll(heads);
    result.revisions.addAll(revisions);
    for (final entry in events.entries) {
      result.events[entry.key] = List<CollaborationEvent>.of(entry.value);
    }
    result.presence.addAll(presence);
    result.comments.addAll(comments);
    result.approvals.addAll(approvals);
    result.releases.addAll(releases);
    result.audit.addAll(audit);
    result.pushes.addAll(pushes);
    return result;
  }
}

final class _StoredPush {
  const _StoredPush({
    required this.requestDigest,
    required this.revision,
    required this.event,
    required this.expiresAt,
  });

  final Digest requestDigest;
  final WorkspaceRevision revision;
  final CollaborationEvent event;
  final DateTime expiresAt;
}

final class _InMemoryHostedTransaction
    implements HostedCollaborationTransaction {
  _InMemoryHostedTransaction(this.context, this.state);

  final HostedRequestContext context;
  final _TenantState state;

  @override
  Future<MembershipRole?> roleFor(String principalId) async =>
      state.roles[principalId];

  @override
  Future<Digest?> workspaceHead(String workspaceId) async =>
      state.heads[workspaceId];

  @override
  Future<StoredPushResponse?> pushByIdempotencyKey(
    String principalId,
    String key,
  ) async {
    final stored = state.pushes['$principalId\u0000$key'];
    if (stored == null) return null;
    return StoredPushResponse(
      requestDigest: stored.requestDigest,
      revision: stored.revision,
      event: stored.event,
    );
  }

  @override
  Future<void> insertRevision(WorkspaceRevision revision) async {
    _tenant(revision.tenantId);
    if (state.revisions.containsKey(revision.digest)) {
      throw StateError('revision already exists');
    }
    state.revisions[revision.digest] = revision;
  }

  @override
  Future<void> setWorkspaceHead(
    String workspaceId,
    Digest revisionDigest,
  ) async {
    if (!state.revisions.containsKey(revisionDigest)) {
      throw StateError('head must reference a persisted revision');
    }
    state.heads[workspaceId] = revisionDigest;
  }

  @override
  Future<CollaborationEvent> appendEvent({
    required String workspaceId,
    required CollaborationEventKind kind,
    required Digest subjectDigest,
    required String principalId,
    required DateTime occurredAt,
    required Map<String, Object?> payload,
  }) async {
    final target = state.events.putIfAbsent(
      workspaceId,
      () => <CollaborationEvent>[],
    );
    final event = CollaborationEvent(
      tenantId: context.tenantId,
      workspaceId: workspaceId,
      sequence: target.length + 1,
      kind: kind,
      subjectDigest: subjectDigest,
      principalId: principalId,
      occurredAt: occurredAt,
      payload: payload,
    );
    target.add(event);
    return event;
  }

  @override
  Future<void> appendAudit(AuditEvent event) async {
    _tenant(event.tenantId);
    state.audit.add(event);
  }

  @override
  Future<void> rememberPush({
    required String principalId,
    required String key,
    required Digest requestDigest,
    required WorkspaceRevision revision,
    required CollaborationEvent event,
    required DateTime expiresAt,
  }) async {
    state.pushes['$principalId\u0000$key'] = _StoredPush(
      requestDigest: requestDigest,
      revision: revision,
      event: event,
      expiresAt: expiresAt,
    );
  }

  @override
  Future<List<CollaborationEvent>> replayEvents({
    required String workspaceId,
    required int afterSequence,
    required int limit,
  }) async => List<CollaborationEvent>.unmodifiable(
    (state.events[workspaceId] ?? const <CollaborationEvent>[])
        .where((event) => event.sequence > afterSequence)
        .take(limit),
  );

  @override
  Future<void> upsertPresence(PresenceLease lease) async {
    _tenant(lease.tenantId);
    state.presence['${lease.workspaceId}\u0000${lease.sessionId}'] = lease;
  }

  @override
  Future<List<PresenceLease>> activePresence({
    required String workspaceId,
    required DateTime now,
  }) async {
    state.presence.removeWhere((_, lease) => !lease.expiresAt.isAfter(now));
    final active =
        state.presence.values
            .where((lease) => lease.workspaceId == workspaceId)
            .toList(growable: false)
          ..sort((left, right) => left.sessionId.compareTo(right.sessionId));
    return List<PresenceLease>.unmodifiable(active);
  }

  @override
  Future<void> addComment(CommentThread thread) async {
    _tenant(thread.tenantId);
    if (state.comments.containsKey(thread.id)) {
      throw StateError('comment thread already exists');
    }
    state.comments[thread.id] = thread;
  }

  @override
  Future<void> addApproval({
    required String workspaceId,
    required Approval approval,
  }) async {
    if (workspaceId.isEmpty) throw ArgumentError.value(workspaceId);
    state.approvals.add(approval);
  }

  @override
  Future<void> addRelease({
    required String workspaceId,
    required Release release,
    required String principalId,
  }) async {
    if (workspaceId.isEmpty || principalId.isEmpty) {
      throw ArgumentError('workspace and principal are required');
    }
    if (state.releases.containsKey(release.digest)) {
      throw StateError('release already exists');
    }
    state.releases[release.digest] = release;
  }

  void _tenant(String tenantId) {
    if (tenantId != context.tenantId) {
      throw const HostedAuthorizationException('cross-tenant write rejected');
    }
  }
}
