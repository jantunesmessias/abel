import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:postgres/postgres.dart';

final class PostgresRemoteSchedulerRepository
    implements RemoteSchedulerRepository {
  const PostgresRemoteSchedulerRepository({
    required this._tenantDatabase,
    required this._schedulerDatabase,
  });

  final SessionExecutor _tenantDatabase;

  /// Uses a dedicated scheduler principal that may only list expired lease
  /// tenant IDs. It must not be reused by API handlers or workers.
  final SessionExecutor _schedulerDatabase;

  @override
  Future<T> inTenantTransaction<T>(
    String tenantId,
    Future<T> Function(RemoteSchedulerTransaction transaction) operation,
  ) => _tenantDatabase.runTx(
    (session) async {
      await session.execute(
        Sql.named(
          "SELECT set_config('control_plane.tenant_id', @tenant:text, true)",
        ),
        parameters: <String, Object?>{'tenant': tenantId},
      );
      return operation(_PostgresRemoteTransaction(session, tenantId));
    },
    settings: TransactionSettings(
      isolationLevel: IsolationLevel.serializable,
      accessMode: AccessMode.readWrite,
    ),
  );

  @override
  Future<List<String>> tenantsWithExpiredLeases(DateTime now) =>
      _schedulerDatabase.run((session) async {
        final rows = await session.execute(
          Sql.named('''
            SELECT tenant_id
            FROM control_plane.scheduler_expired_tenants(@now:timestamptz)
          '''),
          parameters: <String, Object?>{'now': now},
        );
        return rows.map((row) => row[0]! as String).toList(growable: false);
      });

  @override
  Future<List<String>> tenantsWithQueuedRuns() =>
      _schedulerDatabase.run((session) async {
        final rows = await session.execute('''
          SELECT tenant_id
          FROM control_plane.scheduler_queued_tenants()
        ''');
        return rows.map((row) => row[0]! as String).toList(growable: false);
      });

  @override
  Future<List<String>> tenantsWithPendingCleanups(DateTime now) =>
      _schedulerDatabase.run((session) async {
        final rows = await session.execute(
          Sql.named('''
            SELECT tenant_id
            FROM control_plane.scheduler_cleanup_tenants(@now:timestamptz)
          '''),
          parameters: <String, Object?>{'now': now},
        );
        return rows.map((row) => row[0]! as String).toList(growable: false);
      });
}

final class _PostgresRemoteTransaction implements RemoteSchedulerTransaction {
  const _PostgresRemoteTransaction(this._session, this._tenantId);

  final TxSession _session;
  final String _tenantId;

  @override
  Future<int> countQueued() => _count("state = 'queued'");

  @override
  Future<int> countConcurrent() =>
      _count("state IN ('scheduled', 'provisioning', 'running', 'uploading')");

  @override
  Future<int> countInteractive() => _count(
    "mode = 'interactive' AND state NOT IN "
    "('succeeded', 'failed', 'cancelled', 'unknown')",
  );

  Future<int> _count(String predicate) async {
    final rows = await _session.execute(
      Sql.named('''
        SELECT count(*)::integer
        FROM control_plane.remote_runs
        WHERE tenant_id = @tenant:text AND $predicate
      '''),
      parameters: <String, Object?>{'tenant': _tenantId},
    );
    return rows.single[0]! as int;
  }

  @override
  Future<void> insert({
    required RemoteExecutionRequest request,
    required RemoteExecutionPlan plan,
    required RemoteRun run,
  }) async {
    _sameTenant(request.tenantId);
    _sameTenant(plan.tenantId);
    _sameTenant(run.tenantId);
    await _session.execute(
      Sql.named('''
        INSERT INTO control_plane.remote_requests (
          tenant_id, request_id, request_digest, workspace_id, requested_by,
          target, mode, priority, document, requested_at
        ) VALUES (
          @tenant:text, @request_id:text, @request_digest:text,
          @workspace:text, @requested_by:text, @target:text, @mode:text,
          @priority:int4, @document:jsonb, @requested_at:timestamptz
        )
      '''),
      parameters: <String, Object?>{
        'tenant': _tenantId,
        'request_id': request.id,
        'request_digest': request.digest.value,
        'workspace': request.workspaceId,
        'requested_by': request.requestedBy,
        'target': request.target.name,
        'mode': request.mode.name,
        'priority': request.priority,
        'document': request.toJson(),
        'requested_at': request.requestedAt,
      },
    );
    await _session.execute(
      Sql.named('''
        INSERT INTO control_plane.remote_plans (
          tenant_id, run_id, plan_digest, request_digest,
          document, issued_at, expires_at
        ) VALUES (
          @tenant:text, @run_id:text, @plan_digest:text, @request_digest:text,
          @document:jsonb, @issued_at:timestamptz, @expires_at:timestamptz
        )
      '''),
      parameters: <String, Object?>{
        'tenant': _tenantId,
        'run_id': run.id,
        'plan_digest': plan.digest.value,
        'request_digest': request.digest.value,
        'document': plan.toJson(),
        'issued_at': plan.issuedAt,
        'expires_at': plan.expiresAt,
      },
    );
    await _insertRun(run);
  }

  Future<void> _insertRun(RemoteRun run) async {
    await _session.execute(
      Sql.named('''
        INSERT INTO control_plane.remote_runs (
          tenant_id, run_id, request_digest, plan_digest, target, mode,
          state, attempt, worker_id, failure_code, created_at, updated_at
        ) VALUES (
          @tenant:text, @run_id:text, @request_digest:text, @plan_digest:text,
          @target:text, @mode:text, @state:text, @attempt:int4,
          @worker_id:text, @failure_code:text, @created_at:timestamptz,
          @updated_at:timestamptz
        )
      '''),
      parameters: _runParameters(run),
    );
  }

  @override
  Future<List<RemoteRun>> queuedFor(Set<RemoteTargetKind> targets) async {
    if (targets.isEmpty) return const <RemoteRun>[];
    final rows = await _session.execute(
      Sql.named('''
        SELECT r.*
        FROM control_plane.remote_runs r
        JOIN control_plane.remote_requests q
          ON q.tenant_id = r.tenant_id AND q.request_digest = r.request_digest
        WHERE r.tenant_id = @tenant:text
          AND r.state = 'queued'
          AND r.target = ANY(@targets:_text)
          AND NOT EXISTS (
            SELECT 1
            FROM control_plane.remote_cleanup_tasks cleanup
            WHERE cleanup.tenant_id = r.tenant_id
              AND cleanup.run_id = r.run_id
          )
        ORDER BY q.priority DESC, q.requested_at ASC, r.run_id ASC
        FOR UPDATE OF r SKIP LOCKED
      '''),
      parameters: <String, Object?>{
        'tenant': _tenantId,
        'targets': targets.map((target) => target.name).toList(),
      },
    );
    return rows.map(_runFromRow).toList(growable: false);
  }

  @override
  Future<RemoteExecutionPlan> planFor(String runId) async {
    final rows = await _session.execute(
      Sql.named('''
        SELECT document
        FROM control_plane.remote_plans
        WHERE tenant_id = @tenant:text AND run_id = @run_id:text
      '''),
      parameters: _runIdParameters(runId),
    );
    if (rows.isEmpty) throw const RemoteStateException('remote plan not found');
    return RemoteExecutionPlan.fromJson(rows.single[0]);
  }

  @override
  Future<RemoteExecutionRequest> requestFor(String runId) async {
    final rows = await _session.execute(
      Sql.named('''
        SELECT q.document
        FROM control_plane.remote_runs r
        JOIN control_plane.remote_requests q
          ON q.tenant_id = r.tenant_id
         AND q.request_digest = r.request_digest
        WHERE r.tenant_id = @tenant:text AND r.run_id = @run:text
      '''),
      parameters: <String, Object?>{'tenant': _tenantId, 'run': runId},
    );
    if (rows.length != 1) throw StateError('remote request not found');
    return RemoteExecutionRequest.fromJson(rows.single[0]);
  }

  @override
  Future<RemoteRun?> runById(String runId) async {
    final rows = await _session.execute(
      Sql.named('''
        SELECT * FROM control_plane.remote_runs
        WHERE tenant_id = @tenant:text AND run_id = @run_id:text
        FOR UPDATE
      '''),
      parameters: _runIdParameters(runId),
    );
    return rows.isEmpty ? null : _runFromRow(rows.single);
  }

  @override
  Future<RemoteLease?> leaseFor(String runId) async {
    final rows = await _session.execute(
      Sql.named('''
        SELECT * FROM control_plane.remote_leases
        WHERE tenant_id = @tenant:text AND run_id = @run_id:text
        FOR UPDATE
      '''),
      parameters: _runIdParameters(runId),
    );
    return rows.isEmpty ? null : _leaseFromRow(rows.single);
  }

  @override
  Future<int> activeLeaseCount(String workerId, DateTime now) async {
    final rows = await _session.execute(
      Sql.named('''
        SELECT count(*)::integer
        FROM control_plane.remote_leases
        WHERE tenant_id = @tenant:text
          AND worker_id = @worker:text
          AND expires_at > @now:timestamptz
      '''),
      parameters: <String, Object?>{
        'tenant': _tenantId,
        'worker': workerId,
        'now': now,
      },
    );
    return rows.single[0]! as int;
  }

  @override
  Future<void> replaceRun(RemoteRun run, RemoteRunState expectedState) async {
    _sameTenant(run.tenantId);
    final result = await _session.execute(
      Sql.named('''
        UPDATE control_plane.remote_runs
        SET state = @state:text,
            attempt = @attempt:int4,
            worker_id = @worker_id:text,
            failure_code = @failure_code:text,
            updated_at = @updated_at:timestamptz
        WHERE tenant_id = @tenant:text
          AND run_id = @run_id:text
          AND state = @expected_state:text
      '''),
      parameters: <String, Object?>{
        'tenant': run.tenantId,
        'run_id': run.id,
        'state': run.state.name,
        'attempt': run.attempt,
        'worker_id': run.workerId,
        'failure_code': run.failureCode,
        'updated_at': run.updatedAt,
        'expected_state': expectedState.name,
      },
    );
    if (result.affectedRows != 1) {
      throw const RemoteStateException('remote run compare-and-set failed');
    }
  }

  @override
  Future<void> putLease(RemoteLease lease) async {
    _sameTenant(lease.tenantId);
    final result = await _session.execute(
      Sql.named('''
        INSERT INTO control_plane.remote_leases (
          tenant_id, run_id, worker_id, token_id, generation,
          acquired_at, heartbeat_at, expires_at
        ) VALUES (
          @tenant:text, @run_id:text, @worker:text, @token:text,
          @generation:int4, @acquired_at:timestamptz,
          @heartbeat_at:timestamptz, @expires_at:timestamptz
        )
        ON CONFLICT (tenant_id, run_id) DO UPDATE SET
          heartbeat_at = EXCLUDED.heartbeat_at,
          expires_at = EXCLUDED.expires_at
        WHERE remote_leases.worker_id = EXCLUDED.worker_id
          AND remote_leases.token_id = EXCLUDED.token_id
          AND remote_leases.generation = EXCLUDED.generation
      '''),
      parameters: <String, Object?>{
        'tenant': lease.tenantId,
        'run_id': lease.runId,
        'worker': lease.workerId,
        'token': lease.tokenId,
        'generation': lease.generation,
        'acquired_at': lease.acquiredAt,
        'heartbeat_at': lease.heartbeatAt,
        'expires_at': lease.expiresAt,
      },
    );
    if (result.affectedRows != 1) {
      throw const RemoteStateException('exclusive remote lease rejected');
    }
  }

  @override
  Future<void> removeLease(String runId, int generation) async {
    final result = await _session.execute(
      Sql.named('''
        DELETE FROM control_plane.remote_leases
        WHERE tenant_id = @tenant:text
          AND run_id = @run_id:text
          AND generation = @generation:int4
      '''),
      parameters: <String, Object?>{
        ..._runIdParameters(runId),
        'generation': generation,
      },
    );
    if (result.affectedRows > 1) {
      throw StateError('remote lease uniqueness invariant failed');
    }
  }

  @override
  Future<void> putCompletion({
    required RemoteArtifactManifest artifacts,
    required RemoteContainmentReport containment,
  }) async {
    _sameTenant(artifacts.tenantId);
    _sameTenant(containment.tenantId);
    if (artifacts.runId != containment.runId) {
      throw const RemoteStateException('remote completion run mismatch');
    }
    await _session.execute(
      Sql.named('''
        INSERT INTO control_plane.remote_artifact_manifests (
          tenant_id, run_id, manifest_digest, document, created_at,
          interactive_transport
        ) VALUES (
          @tenant:text, @run:text, @digest:text, @document:jsonb,
          @created:timestamptz, @transport:text
        )
      '''),
      parameters: <String, Object?>{
        'tenant': _tenantId,
        'run': artifacts.runId,
        'digest': artifacts.digest.value,
        'document': artifacts.toJson(),
        'created': artifacts.createdAt,
        'transport': artifacts.interactiveTransport.name,
      },
    );
    await _session.execute(
      Sql.named('''
        INSERT INTO control_plane.remote_containment_reports (
          tenant_id, run_id, report_digest, document, observed_at
        ) VALUES (
          @tenant:text, @run:text, @digest:text, @document:jsonb,
          @observed:timestamptz
        )
      '''),
      parameters: <String, Object?>{
        'tenant': _tenantId,
        'run': containment.runId,
        'digest': containment.digest.value,
        'document': containment.toJson(),
        'observed': containment.observedAt,
      },
    );
  }

  @override
  Future<List<RemoteLease>> expiredLeases(DateTime now) async {
    final rows = await _session.execute(
      Sql.named('''
        SELECT * FROM control_plane.remote_leases
        WHERE tenant_id = @tenant:text AND expires_at <= @now:timestamptz
        ORDER BY run_id
        FOR UPDATE SKIP LOCKED
      '''),
      parameters: <String, Object?>{'tenant': _tenantId, 'now': now},
    );
    return rows.map(_leaseFromRow).toList(growable: false);
  }

  @override
  Future<void> putCleanup(RemoteCleanupTask task) async {
    _sameTenant(task.tenantId);
    await _session.execute(
      Sql.named('''
        INSERT INTO control_plane.remote_cleanup_tasks (
          tenant_id, run_id, generation, requested_at, available_at,
          attempts, last_failure_code
        ) VALUES (
          @tenant:text, @run:text, @generation:int4,
          @requested:timestamptz, @available:timestamptz,
          @attempts:int4, @failure:text
        )
        ON CONFLICT (tenant_id, run_id, generation) DO NOTHING
      '''),
      parameters: _cleanupParameters(task),
    );
  }

  @override
  Future<List<RemoteCleanupTask>> readyCleanups(DateTime now, int limit) async {
    final rows = await _session.execute(
      Sql.named('''
        SELECT *
        FROM control_plane.remote_cleanup_tasks
        WHERE tenant_id = @tenant:text
          AND available_at <= @now:timestamptz
        ORDER BY available_at, run_id, generation
        LIMIT @limit:int4
        FOR UPDATE SKIP LOCKED
      '''),
      parameters: <String, Object?>{
        'tenant': _tenantId,
        'now': now,
        'limit': limit,
      },
    );
    return rows.map(_cleanupFromRow).toList(growable: false);
  }

  @override
  Future<void> completeCleanup(RemoteCleanupTask task) async {
    _sameTenant(task.tenantId);
    final result = await _session.execute(
      Sql.named('''
        DELETE FROM control_plane.remote_cleanup_tasks
        WHERE tenant_id = @tenant:text
          AND run_id = @run:text
          AND generation = @generation:int4
          AND attempts = @attempts:int4
          AND available_at = @available:timestamptz
      '''),
      parameters: <String, Object?>{
        'tenant': task.tenantId,
        'run': task.runId,
        'generation': task.generation,
        'attempts': task.attempts,
        'available': task.availableAt,
      },
    );
    if (result.affectedRows == 0 && !await _cleanupExists(task)) return;
    if (result.affectedRows != 1) {
      throw const RemoteStateException('stale remote cleanup acknowledgement');
    }
  }

  @override
  Future<void> deferCleanup(
    RemoteCleanupTask task, {
    required DateTime availableAt,
    required String failureCode,
  }) async {
    _sameTenant(task.tenantId);
    final result = await _session.execute(
      Sql.named('''
        UPDATE control_plane.remote_cleanup_tasks
        SET available_at = @next_available:timestamptz,
            attempts = attempts + 1,
            last_failure_code = @next_failure:text
        WHERE tenant_id = @tenant:text
          AND run_id = @run:text
          AND generation = @generation:int4
          AND attempts = @attempts:int4
          AND available_at = @available:timestamptz
      '''),
      parameters: <String, Object?>{
        'tenant': task.tenantId,
        'run': task.runId,
        'generation': task.generation,
        'attempts': task.attempts,
        'available': task.availableAt,
        'next_available': availableAt,
        'next_failure': failureCode,
      },
    );
    if (result.affectedRows == 0 && !await _cleanupExists(task)) return;
    if (result.affectedRows != 1) {
      throw const RemoteStateException('stale remote cleanup deferral');
    }
  }

  RemoteRun _runFromRow(ResultRow row) {
    final value = row.toColumnMap();
    return RemoteRun(
      tenantId: value['tenant_id']! as String,
      id: value['run_id']! as String,
      requestDigest: Digest(value['request_digest']! as String),
      planDigest: Digest(value['plan_digest']! as String),
      target: RemoteTargetKind.values.singleWhere(
        (item) => item.name == value['target'],
      ),
      mode: RemoteRunMode.values.singleWhere(
        (item) => item.name == value['mode'],
      ),
      state: RemoteRunState.values.singleWhere(
        (item) => item.name == value['state'],
      ),
      attempt: value['attempt']! as int,
      createdAt: (value['created_at']! as DateTime).toUtc(),
      updatedAt: (value['updated_at']! as DateTime).toUtc(),
      workerId: value['worker_id'] as String?,
      failureCode: value['failure_code'] as String?,
    );
  }

  Future<bool> _cleanupExists(RemoteCleanupTask task) async {
    final rows = await _session.execute(
      Sql.named('''
        SELECT 1
        FROM control_plane.remote_cleanup_tasks
        WHERE tenant_id = @tenant:text
          AND run_id = @run:text
          AND generation = @generation:int4
      '''),
      parameters: <String, Object?>{
        'tenant': task.tenantId,
        'run': task.runId,
        'generation': task.generation,
      },
    );
    return rows.isNotEmpty;
  }

  RemoteLease _leaseFromRow(ResultRow row) {
    final value = row.toColumnMap();
    return RemoteLease(
      tenantId: value['tenant_id']! as String,
      runId: value['run_id']! as String,
      workerId: value['worker_id']! as String,
      tokenId: value['token_id']! as String,
      generation: value['generation']! as int,
      acquiredAt: (value['acquired_at']! as DateTime).toUtc(),
      heartbeatAt: (value['heartbeat_at']! as DateTime).toUtc(),
      expiresAt: (value['expires_at']! as DateTime).toUtc(),
    );
  }

  RemoteCleanupTask _cleanupFromRow(ResultRow row) {
    final value = row.toColumnMap();
    return RemoteCleanupTask(
      tenantId: value['tenant_id']! as String,
      runId: value['run_id']! as String,
      generation: value['generation']! as int,
      requestedAt: (value['requested_at']! as DateTime).toUtc(),
      availableAt: (value['available_at']! as DateTime).toUtc(),
      attempts: value['attempts']! as int,
      lastFailureCode: value['last_failure_code'] as String?,
    );
  }

  Map<String, Object?> _runParameters(RemoteRun run) => <String, Object?>{
    'tenant': run.tenantId,
    'run_id': run.id,
    'request_digest': run.requestDigest.value,
    'plan_digest': run.planDigest.value,
    'target': run.target.name,
    'mode': run.mode.name,
    'state': run.state.name,
    'attempt': run.attempt,
    'worker_id': run.workerId,
    'failure_code': run.failureCode,
    'created_at': run.createdAt,
    'updated_at': run.updatedAt,
  };

  Map<String, Object?> _runIdParameters(String runId) => <String, Object?>{
    'tenant': _tenantId,
    'run_id': runId,
  };

  Map<String, Object?> _cleanupParameters(RemoteCleanupTask task) =>
      <String, Object?>{
        'tenant': task.tenantId,
        'run': task.runId,
        'generation': task.generation,
        'requested': task.requestedAt,
        'available': task.availableAt,
        'attempts': task.attempts,
        'failure': task.lastFailureCode,
      };

  void _sameTenant(String tenantId) {
    if (tenantId != _tenantId) {
      throw const HostedAuthorizationException(
        'cross-tenant remote write rejected',
      );
    }
  }
}
