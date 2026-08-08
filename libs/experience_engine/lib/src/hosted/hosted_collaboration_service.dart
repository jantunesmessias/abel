import 'package:experience_contracts/experience_contracts.dart';

import '../ports.dart';

final class HostedRequestContext {
  const HostedRequestContext({
    required this.tenantId,
    required this.principalId,
    required this.correlationId,
  });

  final String tenantId;
  final String principalId;
  final String correlationId;
}

enum HostedPermission { read, comment, approve, push, publish, administer }

final class HostedAuthorizationPolicy {
  const HostedAuthorizationPolicy();

  bool allows(MembershipRole role, HostedPermission permission) =>
      switch (role) {
        MembershipRole.owner => true,
        MembershipRole.admin => true,
        MembershipRole.editor => const <HostedPermission>{
          HostedPermission.read,
          HostedPermission.comment,
          HostedPermission.push,
          HostedPermission.publish,
        }.contains(permission),
        MembershipRole.reviewer => const <HostedPermission>{
          HostedPermission.read,
          HostedPermission.comment,
          HostedPermission.approve,
        }.contains(permission),
        MembershipRole.viewer => permission == HostedPermission.read,
      };
}

final class HostedAuthorizationException implements Exception {
  const HostedAuthorizationException(this.message);

  final String message;

  @override
  String toString() => 'HostedAuthorizationException: $message';
}

final class HostedIdempotencyException implements Exception {
  const HostedIdempotencyException(this.message);

  final String message;

  @override
  String toString() => 'HostedIdempotencyException: $message';
}

final class HostedConcurrencyException implements Exception {
  const HostedConcurrencyException(this.conflict);

  final WorkspaceConflict conflict;

  @override
  String toString() => 'HostedConcurrencyException: ${conflict.toJson()}';
}

sealed class WorkspacePushResult {
  const WorkspacePushResult();
}

final class WorkspacePushAccepted extends WorkspacePushResult {
  const WorkspacePushAccepted({
    required this.revision,
    required this.event,
    required this.replayed,
  });

  final WorkspaceRevision revision;
  final CollaborationEvent event;
  final bool replayed;

  Digest get responseDigest => Digest.semantic(<String, Object?>{
    'revision': revision.toJson(),
    'event': event.toJson(),
  });
}

final class WorkspacePushRejected extends WorkspacePushResult {
  const WorkspacePushRejected(this.conflict);

  final WorkspaceConflict conflict;
}

final class StoredPushResponse {
  const StoredPushResponse({
    required this.requestDigest,
    required this.revision,
    required this.event,
  });

  final Digest requestDigest;
  final WorkspaceRevision revision;
  final CollaborationEvent event;
}

abstract interface class HostedCollaborationTransaction {
  Future<MembershipRole?> roleFor(String principalId);

  Future<Digest?> workspaceHead(String workspaceId);

  Future<StoredPushResponse?> pushByIdempotencyKey(
    String principalId,
    String key,
  );

  Future<void> insertRevision(WorkspaceRevision revision);

  Future<void> setWorkspaceHead(String workspaceId, Digest revisionDigest);

  Future<CollaborationEvent> appendEvent({
    required String workspaceId,
    required CollaborationEventKind kind,
    required Digest subjectDigest,
    required String principalId,
    required DateTime occurredAt,
    required Map<String, Object?> payload,
  });

  Future<void> appendAudit(AuditEvent event);

  Future<void> rememberPush({
    required String principalId,
    required String key,
    required Digest requestDigest,
    required WorkspaceRevision revision,
    required CollaborationEvent event,
    required DateTime expiresAt,
  });

  Future<List<CollaborationEvent>> replayEvents({
    required String workspaceId,
    required int afterSequence,
    required int limit,
  });

  Future<void> upsertPresence(PresenceLease lease);

  Future<List<PresenceLease>> activePresence({
    required String workspaceId,
    required DateTime now,
  });

  Future<void> addComment(CommentThread thread);

  Future<void> addApproval({
    required String workspaceId,
    required Approval approval,
  });

  Future<void> addRelease({
    required String workspaceId,
    required Release release,
    required String principalId,
  });
}

abstract interface class HostedCollaborationRepository {
  Future<T> inTenantTransaction<T>(
    HostedRequestContext context,
    Future<T> Function(HostedCollaborationTransaction transaction) operation,
  );
}

final class HostedCollaborationService {
  const HostedCollaborationService({
    required this._repository,
    required this._clock,
    required this._ids,
    this._authorization = const HostedAuthorizationPolicy(),
  });

  final HostedCollaborationRepository _repository;
  final Clock _clock;
  final IdGenerator _ids;
  final HostedAuthorizationPolicy _authorization;

  Future<void> authorize(
    HostedRequestContext context,
    HostedPermission permission,
  ) => _repository.inTenantTransaction(
    context,
    (transaction) => _authorize(transaction, context, permission),
  );

  Future<WorkspacePushResult> push(
    HostedRequestContext context,
    WorkspaceChangeSet changeSet,
  ) => _repository.inTenantTransaction(context, (transaction) async {
    _sameContext(context, changeSet.tenantId, changeSet.principalId);
    await _authorize(transaction, context, HostedPermission.push);
    final previous = await transaction.pushByIdempotencyKey(
      context.principalId,
      changeSet.idempotencyKey,
    );
    if (previous != null) {
      if (previous.requestDigest != changeSet.digest) {
        throw const HostedIdempotencyException(
          'idempotency key was already used for another request',
        );
      }
      return WorkspacePushAccepted(
        revision: previous.revision,
        event: previous.event,
        replayed: true,
      );
    }

    final current = await transaction.workspaceHead(changeSet.workspaceId);
    if (current != changeSet.expectedDigest) {
      return WorkspacePushRejected(
        WorkspaceConflict(
          tenantId: context.tenantId,
          workspaceId: changeSet.workspaceId,
          baseDigest: changeSet.baseDigest,
          currentDigest: current ?? Digest.semantic(const <String, Object?>{}),
          proposedDigest: changeSet.proposedDigest,
        ),
      );
    }
    final now = _clock.nowUtc();
    final revision = WorkspaceRevision(
      tenantId: context.tenantId,
      workspaceId: changeSet.workspaceId,
      id: _ids.nextId(),
      contentDigest: changeSet.proposedDigest,
      changeSetDigest: changeSet.digest,
      parentDigest: current,
      createdAt: now,
      createdBy: context.principalId,
    );
    await transaction.insertRevision(revision);
    await transaction.setWorkspaceHead(changeSet.workspaceId, revision.digest);
    final event = await transaction.appendEvent(
      workspaceId: changeSet.workspaceId,
      kind: CollaborationEventKind.workspacePushed,
      subjectDigest: revision.digest,
      principalId: context.principalId,
      occurredAt: now,
      payload: <String, Object?>{
        'revisionDigest': revision.digest.value,
        'contentDigest': revision.contentDigest.value,
        'correlationId': context.correlationId,
      },
    );
    await transaction.appendAudit(
      AuditEvent(
        tenantId: context.tenantId,
        id: _ids.nextId(),
        principalId: context.principalId,
        action: 'workspace.push',
        subjectDigest: revision.digest,
        occurredAt: now,
        context: <String, Object?>{
          'workspaceId': changeSet.workspaceId,
          'correlationId': context.correlationId,
        },
      ),
    );
    await transaction.rememberPush(
      principalId: context.principalId,
      key: changeSet.idempotencyKey,
      requestDigest: changeSet.digest,
      revision: revision,
      event: event,
      expiresAt: now.add(const Duration(hours: 24)),
    );
    return WorkspacePushAccepted(
      revision: revision,
      event: event,
      replayed: false,
    );
  });

  Future<List<CollaborationEvent>> replay(
    HostedRequestContext context, {
    required String workspaceId,
    required int afterSequence,
    int limit = 500,
  }) => _repository.inTenantTransaction(context, (transaction) async {
    if (afterSequence < 0 || limit < 1 || limit > 1000) {
      throw ArgumentError('invalid replay cursor or limit');
    }
    await _authorize(transaction, context, HostedPermission.read);
    return transaction.replayEvents(
      workspaceId: workspaceId,
      afterSequence: afterSequence,
      limit: limit,
    );
  });

  Future<PresenceLease> heartbeat(
    HostedRequestContext context, {
    required String workspaceId,
    required String sessionId,
    Duration ttl = const Duration(seconds: 60),
  }) => _repository.inTenantTransaction(context, (transaction) async {
    await _authorize(transaction, context, HostedPermission.read);
    if (ttl < const Duration(seconds: 10) || ttl > const Duration(minutes: 5)) {
      throw ArgumentError('presence TTL must be between 10 and 300 seconds');
    }
    final lease = PresenceLease(
      tenantId: context.tenantId,
      workspaceId: workspaceId,
      principalId: context.principalId,
      sessionId: sessionId,
      expiresAt: _clock.nowUtc().add(ttl),
    );
    await transaction.upsertPresence(lease);
    return lease;
  });

  Future<List<PresenceLease>> presence(
    HostedRequestContext context, {
    required String workspaceId,
  }) => _repository.inTenantTransaction(context, (transaction) async {
    await _authorize(transaction, context, HostedPermission.read);
    return transaction.activePresence(
      workspaceId: workspaceId,
      now: _clock.nowUtc(),
    );
  });

  Future<CommentThread> comment(
    HostedRequestContext context, {
    required String workspaceId,
    required Digest subjectDigest,
    required String body,
  }) => _repository.inTenantTransaction(context, (transaction) async {
    await _authorize(transaction, context, HostedPermission.comment);
    final now = _clock.nowUtc();
    final thread = CommentThread(
      tenantId: context.tenantId,
      workspaceId: workspaceId,
      id: _ids.nextId(),
      subjectDigest: subjectDigest,
      comments: <CommentEntry>[
        CommentEntry(
          id: _ids.nextId(),
          principalId: context.principalId,
          body: body,
          createdAt: now,
        ),
      ],
      resolved: false,
    );
    await transaction.addComment(thread);
    await transaction.appendEvent(
      workspaceId: workspaceId,
      kind: CollaborationEventKind.commentAdded,
      subjectDigest: subjectDigest,
      principalId: context.principalId,
      occurredAt: now,
      payload: <String, Object?>{'threadId': thread.id},
    );
    return thread;
  });

  Future<Approval> approve(
    HostedRequestContext context, {
    required String workspaceId,
    required Digest subjectDigest,
    required bool approved,
  }) => _repository.inTenantTransaction(context, (transaction) async {
    await _authorize(transaction, context, HostedPermission.approve);
    final now = _clock.nowUtc();
    final approval = Approval(
      id: _ids.nextId(),
      subjectDigest: subjectDigest,
      principalId: context.principalId,
      decidedAt: now,
      approved: approved,
    );
    await transaction.addApproval(workspaceId: workspaceId, approval: approval);
    await transaction.appendEvent(
      workspaceId: workspaceId,
      kind: CollaborationEventKind.approvalRecorded,
      subjectDigest: subjectDigest,
      principalId: context.principalId,
      occurredAt: now,
      payload: <String, Object?>{
        'approvalId': approval.id,
        'approved': approved,
      },
    );
    return approval;
  });

  Future<CollaborationEvent> publish(
    HostedRequestContext context, {
    required String workspaceId,
    required Digest expectedDigest,
    required Release release,
  }) => _repository.inTenantTransaction(context, (transaction) async {
    await _authorize(transaction, context, HostedPermission.publish);
    final current = await transaction.workspaceHead(workspaceId);
    if (current != expectedDigest) {
      throw HostedConcurrencyException(
        WorkspaceConflict(
          tenantId: context.tenantId,
          workspaceId: workspaceId,
          baseDigest: expectedDigest,
          currentDigest: current ?? Digest.semantic(const <String, Object?>{}),
          proposedDigest: release.digest,
        ),
      );
    }
    await transaction.addRelease(
      workspaceId: workspaceId,
      release: release,
      principalId: context.principalId,
    );
    final now = _clock.nowUtc();
    final event = await transaction.appendEvent(
      workspaceId: workspaceId,
      kind: CollaborationEventKind.releasePublished,
      subjectDigest: release.digest,
      principalId: context.principalId,
      occurredAt: now,
      payload: <String, Object?>{
        'releaseDigest': release.digest.value,
        'correlationId': context.correlationId,
      },
    );
    await transaction.appendAudit(
      AuditEvent(
        tenantId: context.tenantId,
        id: _ids.nextId(),
        principalId: context.principalId,
        action: 'release.publish',
        subjectDigest: release.digest,
        occurredAt: now,
        context: <String, Object?>{
          'workspaceId': workspaceId,
          'correlationId': context.correlationId,
        },
      ),
    );
    return event;
  });

  Future<void> _authorize(
    HostedCollaborationTransaction transaction,
    HostedRequestContext context,
    HostedPermission permission,
  ) async {
    final role = await transaction.roleFor(context.principalId);
    if (role == null || !_authorization.allows(role, permission)) {
      throw HostedAuthorizationException(
        '${context.principalId} is not allowed to ${permission.name}',
      );
    }
  }

  void _sameContext(
    HostedRequestContext context,
    String tenantId,
    String principalId,
  ) {
    if (context.tenantId != tenantId || context.principalId != principalId) {
      throw const HostedAuthorizationException(
        'request payload does not match authenticated tenant and principal',
      );
    }
  }
}
