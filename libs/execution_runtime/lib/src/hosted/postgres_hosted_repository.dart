import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:postgres/postgres.dart';

final class PostgresHostedCollaborationRepository
    implements HostedCollaborationRepository {
  const PostgresHostedCollaborationRepository(this._database);

  final SessionExecutor _database;

  @override
  Future<T> inTenantTransaction<T>(
    HostedRequestContext context,
    Future<T> Function(HostedCollaborationTransaction transaction) operation,
  ) => _database.runTx(
    (session) async {
      await session.execute(
        Sql.named('''
          SELECT
            set_config('control_plane.tenant_id', @tenant:text, true),
            set_config('workspace.principal_id', @principal:text, true)
        '''),
        parameters: <String, Object?>{
          'tenant': context.tenantId,
          'principal': context.principalId,
        },
      );
      return operation(_PostgresHostedTransaction(session, context));
    },
    settings: TransactionSettings(
      isolationLevel: IsolationLevel.serializable,
      accessMode: AccessMode.readWrite,
    ),
  );
}

final class _PostgresHostedTransaction
    implements HostedCollaborationTransaction {
  const _PostgresHostedTransaction(this._session, this._context);

  final TxSession _session;
  final HostedRequestContext _context;

  @override
  Future<MembershipRole?> roleFor(String principalId) async {
    final rows = await _session.execute(
      Sql.named('''
        SELECT role
        FROM control_plane.memberships
        WHERE tenant_id = @tenant:text AND principal_id = @principal:text
      '''),
      parameters: <String, Object?>{
        'tenant': _context.tenantId,
        'principal': principalId,
      },
    );
    if (rows.isEmpty) return null;
    final role = rows.single[0]! as String;
    return MembershipRole.values.singleWhere((value) => value.name == role);
  }

  @override
  Future<Digest?> workspaceHead(String workspaceId) async {
    final rows = await _session.execute(
      Sql.named('''
        SELECT revision_digest
        FROM control_plane.workspace_heads
        WHERE tenant_id = @tenant:text AND workspace_id = @workspace:text
        FOR UPDATE
      '''),
      parameters: _workspaceParameters(workspaceId),
    );
    return rows.isEmpty ? null : Digest(rows.single[0]! as String);
  }

  @override
  Future<StoredPushResponse?> pushByIdempotencyKey(
    String principalId,
    String key,
  ) async {
    final rows = await _session.execute(
      Sql.named('''
        SELECT request_digest, response_document
        FROM control_plane.idempotency
        WHERE tenant_id = @tenant:text
          AND principal_id = @principal:text
          AND idempotency_key = @key:text
          AND expires_at > clock_timestamp()
        FOR UPDATE
      '''),
      parameters: <String, Object?>{
        'tenant': _context.tenantId,
        'principal': principalId,
        'key': key,
      },
    );
    if (rows.isEmpty) return null;
    final document = (rows.single[1]! as Map<Object?, Object?>)
        .cast<String, Object?>();
    return StoredPushResponse(
      requestDigest: Digest(rows.single[0]! as String),
      revision: WorkspaceRevision.fromJson(document['revision']),
      event: CollaborationEvent.fromJson(document['event']),
    );
  }

  @override
  Future<void> insertRevision(WorkspaceRevision revision) async {
    _sameTenant(revision.tenantId);
    await _session.execute(
      Sql.named('''
        INSERT INTO control_plane.workspace_revisions (
          tenant_id, workspace_id, revision_id, revision_digest,
          content_digest, change_set_digest, parent_digest, document,
          created_at, created_by
        ) VALUES (
          @tenant:text, @workspace:text, @revision_id:text, @revision_digest:text,
          @content_digest:text, @change_set_digest:text, @parent_digest:text,
          @document:jsonb, @created_at:timestamptz, @created_by:text
        )
      '''),
      parameters: <String, Object?>{
        'tenant': revision.tenantId,
        'workspace': revision.workspaceId,
        'revision_id': revision.id,
        'revision_digest': revision.digest.value,
        'content_digest': revision.contentDigest.value,
        'change_set_digest': revision.changeSetDigest.value,
        'parent_digest': revision.parentDigest?.value,
        'document': revision.toJson(),
        'created_at': revision.createdAt,
        'created_by': revision.createdBy,
      },
    );
  }

  @override
  Future<void> setWorkspaceHead(
    String workspaceId,
    Digest revisionDigest,
  ) async {
    await _session.execute(
      Sql.named('''
        INSERT INTO control_plane.workspace_heads (
          tenant_id, workspace_id, revision_digest, updated_at
        ) VALUES (@tenant:text, @workspace:text, @digest:text, clock_timestamp())
        ON CONFLICT (tenant_id, workspace_id) DO UPDATE
          SET revision_digest = EXCLUDED.revision_digest,
              updated_at = EXCLUDED.updated_at
      '''),
      parameters: <String, Object?>{
        ..._workspaceParameters(workspaceId),
        'digest': revisionDigest.value,
      },
    );
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
    await _session.execute(
      Sql.named('''
        SELECT pg_advisory_xact_lock(
          hashtextextended(@tenant:text || E'\\x1f' || @workspace:text, 0)
        )
      '''),
      parameters: _workspaceParameters(workspaceId),
    );
    final sequenceRows = await _session.execute(
      Sql.named('''
        SELECT COALESCE(MAX(sequence), 0) + 1
        FROM control_plane.collaboration_events
        WHERE tenant_id = @tenant:text AND workspace_id = @workspace:text
      '''),
      parameters: _workspaceParameters(workspaceId),
    );
    final sequence = sequenceRows.single[0]! as int;
    final event = CollaborationEvent(
      tenantId: _context.tenantId,
      workspaceId: workspaceId,
      sequence: sequence,
      kind: kind,
      subjectDigest: subjectDigest,
      principalId: principalId,
      occurredAt: occurredAt,
      payload: payload,
    );
    await _session.execute(
      Sql.named('''
        INSERT INTO control_plane.collaboration_events (
          tenant_id, workspace_id, sequence, event_digest, kind,
          subject_digest, principal_id, occurred_at, payload
        ) VALUES (
          @tenant:text, @workspace:text, @sequence:int8, @event_digest:text,
          @kind:text, @subject_digest:text, @principal:text,
          @occurred_at:timestamptz, @payload:jsonb
        )
      '''),
      parameters: <String, Object?>{
        ..._workspaceParameters(workspaceId),
        'sequence': sequence,
        'event_digest': event.digest.value,
        'kind': kind.name,
        'subject_digest': subjectDigest.value,
        'principal': principalId,
        'occurred_at': occurredAt,
        'payload': payload,
      },
    );
    await _session.execute(
      Sql.named('''
        INSERT INTO control_plane.outbox (
          tenant_id, workspace_id, event_sequence, topic, payload, created_at
        ) VALUES (
          @tenant:text, @workspace:text, @sequence:int8,
          'collaboration.event', @event:jsonb, @occurred_at:timestamptz
        )
      '''),
      parameters: <String, Object?>{
        ..._workspaceParameters(workspaceId),
        'sequence': sequence,
        'event': event.toJson(),
        'occurred_at': occurredAt,
      },
    );
    await _session.execute(
      "SELECT pg_notify('control_plane_collaboration', '')",
    );
    return event;
  }

  @override
  Future<void> appendAudit(AuditEvent event) async {
    _sameTenant(event.tenantId);
    await _session.execute(
      Sql.named('''
        INSERT INTO control_plane.audit_events (
          tenant_id, audit_id, principal_id, action,
          subject_digest, occurred_at, context
        ) VALUES (
          @tenant:text, @audit_id:text, @principal:text, @action:text,
          @subject_digest:text, @occurred_at:timestamptz, @context:jsonb
        )
      '''),
      parameters: <String, Object?>{
        'tenant': event.tenantId,
        'audit_id': event.id,
        'principal': event.principalId,
        'action': event.action,
        'subject_digest': event.subjectDigest.value,
        'occurred_at': event.occurredAt,
        'context': event.context,
      },
    );
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
    final response = <String, Object?>{
      'revision': revision.toJson(),
      'event': event.toJson(),
    };
    await _session.execute(
      Sql.named('''
        INSERT INTO control_plane.idempotency (
          tenant_id, principal_id, idempotency_key, request_digest,
          response_digest, response_document, created_at, expires_at
        ) VALUES (
          @tenant:text, @principal:text, @key:text, @request_digest:text,
          @response_digest:text, @response:jsonb, @created_at:timestamptz,
          @expires_at:timestamptz
        )
      '''),
      parameters: <String, Object?>{
        'tenant': _context.tenantId,
        'principal': principalId,
        'key': key,
        'request_digest': requestDigest.value,
        'response_digest': Digest.semantic(response).value,
        'response': response,
        'created_at': event.occurredAt,
        'expires_at': expiresAt,
      },
    );
  }

  @override
  Future<List<CollaborationEvent>> replayEvents({
    required String workspaceId,
    required int afterSequence,
    required int limit,
  }) async {
    final rows = await _session.execute(
      Sql.named('''
        SELECT sequence, kind, subject_digest, principal_id, occurred_at, payload
        FROM control_plane.collaboration_events
        WHERE tenant_id = @tenant:text
          AND workspace_id = @workspace:text
          AND sequence > @after:int8
        ORDER BY sequence ASC
        LIMIT @limit:int4
      '''),
      parameters: <String, Object?>{
        ..._workspaceParameters(workspaceId),
        'after': afterSequence,
        'limit': limit,
      },
    );
    return List<CollaborationEvent>.unmodifiable(
      rows.map((row) {
        final values = row.toColumnMap();
        return CollaborationEvent(
          tenantId: _context.tenantId,
          workspaceId: workspaceId,
          sequence: values['sequence']! as int,
          kind: CollaborationEventKind.values.singleWhere(
            (value) => value.name == values['kind'],
          ),
          subjectDigest: Digest(values['subject_digest']! as String),
          principalId: values['principal_id']! as String,
          occurredAt: (values['occurred_at']! as DateTime).toUtc(),
          payload: (values['payload']! as Map<Object?, Object?>)
              .cast<String, Object?>(),
        );
      }),
    );
  }

  @override
  Future<void> upsertPresence(PresenceLease lease) async {
    _sameTenant(lease.tenantId);
    await _session.execute(
      Sql.named('''
        INSERT INTO control_plane.presence (
          tenant_id, workspace_id, session_id, principal_id, expires_at
        ) VALUES (
          @tenant:text, @workspace:text, @session:text,
          @principal:text, @expires_at:timestamptz
        )
        ON CONFLICT (tenant_id, workspace_id, session_id) DO UPDATE
          SET principal_id = EXCLUDED.principal_id,
              expires_at = EXCLUDED.expires_at
      '''),
      parameters: <String, Object?>{
        'tenant': lease.tenantId,
        'workspace': lease.workspaceId,
        'session': lease.sessionId,
        'principal': lease.principalId,
        'expires_at': lease.expiresAt,
      },
    );
  }

  @override
  Future<List<PresenceLease>> activePresence({
    required String workspaceId,
    required DateTime now,
  }) async {
    await _session.execute(
      Sql.named('''
        DELETE FROM control_plane.presence
        WHERE tenant_id = @tenant:text
          AND workspace_id = @workspace:text
          AND expires_at <= @now:timestamptz
      '''),
      parameters: <String, Object?>{
        ..._workspaceParameters(workspaceId),
        'now': now,
      },
    );
    final rows = await _session.execute(
      Sql.named('''
        SELECT principal_id, session_id, expires_at
        FROM control_plane.presence
        WHERE tenant_id = @tenant:text AND workspace_id = @workspace:text
        ORDER BY session_id ASC
      '''),
      parameters: _workspaceParameters(workspaceId),
    );
    return List<PresenceLease>.unmodifiable(
      rows.map((row) {
        final values = row.toColumnMap();
        return PresenceLease(
          tenantId: _context.tenantId,
          workspaceId: workspaceId,
          principalId: values['principal_id']! as String,
          sessionId: values['session_id']! as String,
          expiresAt: (values['expires_at']! as DateTime).toUtc(),
        );
      }),
    );
  }

  @override
  Future<void> addComment(CommentThread thread) async {
    _sameTenant(thread.tenantId);
    final first = thread.comments.first;
    await _session.execute(
      Sql.named('''
        INSERT INTO control_plane.comments (
          tenant_id, workspace_id, thread_id, subject_digest,
          document, resolved, created_at, created_by
        ) VALUES (
          @tenant:text, @workspace:text, @thread:text, @subject_digest:text,
          @document:jsonb, @resolved:boolean, @created_at:timestamptz,
          @created_by:text
        )
      '''),
      parameters: <String, Object?>{
        'tenant': thread.tenantId,
        'workspace': thread.workspaceId,
        'thread': thread.id,
        'subject_digest': thread.subjectDigest.value,
        'document': thread.toJson(),
        'resolved': thread.resolved,
        'created_at': first.createdAt,
        'created_by': first.principalId,
      },
    );
  }

  @override
  Future<void> addApproval({
    required String workspaceId,
    required Approval approval,
  }) => _session
      .execute(
        Sql.named('''
      INSERT INTO control_plane.approvals (
        tenant_id, workspace_id, approval_id, subject_digest,
        approved, decided_at, principal_id, document
      ) VALUES (
        @tenant:text, @workspace:text, @approval:text, @subject_digest:text,
        @approved:boolean, @decided_at:timestamptz, @principal:text,
        @document:jsonb
      )
    '''),
        parameters: <String, Object?>{
          ..._workspaceParameters(workspaceId),
          'approval': approval.id,
          'subject_digest': approval.subjectDigest.value,
          'approved': approval.approved,
          'decided_at': approval.decidedAt,
          'principal': approval.principalId,
          'document': approval.toJson(),
        },
        ignoreRows: true,
      )
      .then((_) {});

  @override
  Future<void> addRelease({
    required String workspaceId,
    required Release release,
    required String principalId,
  }) async {
    for (final item in release.evidence) {
      await _session.execute(
        Sql.named('''
          INSERT INTO control_plane.evidence (
            tenant_id, workspace_id, evidence_digest, subject_digest,
            document, created_at, created_by
          ) VALUES (
            @tenant:text, @workspace:text, @digest:text, @subject:text,
            @document:jsonb, @created_at:timestamptz, @principal:text
          )
          ON CONFLICT (tenant_id, workspace_id, evidence_digest) DO NOTHING
        '''),
        parameters: <String, Object?>{
          ..._workspaceParameters(workspaceId),
          'digest': item.digest.value,
          'subject': item.subjectDigest.value,
          'document': item.toJson(),
          'created_at': item.observedAt,
          'principal': principalId,
        },
      );
    }
    await _session.execute(
      Sql.named('''
        INSERT INTO control_plane.releases (
          tenant_id, workspace_id, release_digest, subject_digest,
          document, created_at, created_by
        ) VALUES (
          @tenant:text, @workspace:text, @digest:text, @subject:text,
          @document:jsonb, @created_at:timestamptz, @principal:text
        )
      '''),
      parameters: <String, Object?>{
        ..._workspaceParameters(workspaceId),
        'digest': release.digest.value,
        'subject': release.subjectDigest.value,
        'document': release.toJson(),
        'created_at': release.createdAt,
        'principal': principalId,
      },
    );
  }

  Map<String, Object?> _workspaceParameters(String workspaceId) =>
      <String, Object?>{'tenant': _context.tenantId, 'workspace': workspaceId};

  void _sameTenant(String tenantId) {
    if (tenantId != _context.tenantId) {
      throw const HostedAuthorizationException('cross-tenant write rejected');
    }
  }
}
