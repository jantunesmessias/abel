SET search_path = control_plane, pg_catalog;

CREATE TABLE remote_requests (
  tenant_id text NOT NULL,
  request_id text NOT NULL,
  request_digest text NOT NULL,
  workspace_id text NOT NULL,
  requested_by text NOT NULL,
  target text NOT NULL,
  mode text NOT NULL,
  priority integer NOT NULL,
  document jsonb NOT NULL,
  requested_at timestamptz NOT NULL,
  PRIMARY KEY (tenant_id, request_digest),
  CONSTRAINT remote_requests_id_unique UNIQUE (tenant_id, request_id),
  CONSTRAINT remote_requests_workspace_fk FOREIGN KEY (tenant_id, workspace_id)
    REFERENCES workspaces (tenant_id, workspace_id) ON DELETE CASCADE,
  CONSTRAINT remote_requests_principal_fk FOREIGN KEY (tenant_id, requested_by)
    REFERENCES principals (tenant_id, principal_id),
  CONSTRAINT remote_requests_target_check CHECK (target IN ('web', 'androidEmulator')),
  CONSTRAINT remote_requests_mode_check CHECK (mode IN ('batch', 'interactive')),
  CONSTRAINT remote_requests_priority_check CHECK (priority BETWEEN 0 AND 100)
);

CREATE TABLE remote_plans (
  tenant_id text NOT NULL,
  run_id text NOT NULL,
  plan_digest text NOT NULL,
  request_digest text NOT NULL,
  document jsonb NOT NULL,
  issued_at timestamptz NOT NULL,
  expires_at timestamptz NOT NULL,
  PRIMARY KEY (tenant_id, run_id),
  CONSTRAINT remote_plans_digest_unique UNIQUE (tenant_id, plan_digest),
  CONSTRAINT remote_plans_request_fk FOREIGN KEY (tenant_id, request_digest)
    REFERENCES remote_requests (tenant_id, request_digest) ON DELETE CASCADE,
  CONSTRAINT remote_plans_expiry_check CHECK (expires_at > issued_at)
);

CREATE TABLE remote_runs (
  tenant_id text NOT NULL,
  run_id text NOT NULL,
  request_digest text NOT NULL,
  plan_digest text NOT NULL,
  target text NOT NULL,
  mode text NOT NULL,
  state text NOT NULL,
  attempt integer NOT NULL,
  worker_id text,
  failure_code text,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  PRIMARY KEY (tenant_id, run_id),
  CONSTRAINT remote_runs_request_fk FOREIGN KEY (tenant_id, request_digest)
    REFERENCES remote_requests (tenant_id, request_digest),
  CONSTRAINT remote_runs_plan_fk FOREIGN KEY (tenant_id, plan_digest)
    REFERENCES remote_plans (tenant_id, plan_digest),
  CONSTRAINT remote_runs_state_check CHECK (state IN (
    'queued', 'scheduled', 'provisioning', 'running', 'uploading',
    'succeeded', 'failed', 'cancelled', 'unknown'
  )),
  CONSTRAINT remote_runs_attempt_check CHECK (attempt BETWEEN 0 AND 10)
);

CREATE TABLE remote_workers (
  tenant_id text NOT NULL,
  worker_id text NOT NULL,
  pool text NOT NULL,
  targets text[] NOT NULL,
  maximum_leases integer NOT NULL,
  last_heartbeat_at timestamptz NOT NULL,
  PRIMARY KEY (tenant_id, worker_id),
  CONSTRAINT remote_workers_capacity_check CHECK (maximum_leases BETWEEN 1 AND 32)
);

CREATE TABLE remote_leases (
  tenant_id text NOT NULL,
  run_id text NOT NULL,
  worker_id text NOT NULL,
  token_id text NOT NULL,
  generation integer NOT NULL,
  acquired_at timestamptz NOT NULL,
  heartbeat_at timestamptz NOT NULL,
  expires_at timestamptz NOT NULL,
  PRIMARY KEY (tenant_id, run_id),
  CONSTRAINT remote_leases_token_unique UNIQUE (tenant_id, token_id),
  CONSTRAINT remote_leases_run_fk FOREIGN KEY (tenant_id, run_id)
    REFERENCES remote_runs (tenant_id, run_id) ON DELETE CASCADE,
  CONSTRAINT remote_leases_generation_check CHECK (generation BETWEEN 1 AND 10),
  CONSTRAINT remote_leases_expiry_check CHECK (
    heartbeat_at >= acquired_at AND expires_at > heartbeat_at
  )
);

CREATE TABLE remote_artifact_manifests (
  tenant_id text NOT NULL,
  run_id text NOT NULL,
  manifest_digest text NOT NULL,
  document jsonb NOT NULL,
  created_at timestamptz NOT NULL,
  PRIMARY KEY (tenant_id, run_id, manifest_digest),
  CONSTRAINT remote_artifact_manifests_run_fk FOREIGN KEY (tenant_id, run_id)
    REFERENCES remote_runs (tenant_id, run_id) ON DELETE CASCADE
);

CREATE TABLE remote_containment_reports (
  tenant_id text NOT NULL,
  run_id text NOT NULL,
  report_digest text NOT NULL,
  document jsonb NOT NULL,
  observed_at timestamptz NOT NULL,
  PRIMARY KEY (tenant_id, run_id, report_digest),
  CONSTRAINT remote_containment_reports_run_fk FOREIGN KEY (tenant_id, run_id)
    REFERENCES remote_runs (tenant_id, run_id) ON DELETE CASCADE
);

CREATE INDEX remote_runs_tenant_queue_idx
  ON remote_runs (tenant_id, state, target, created_at, run_id);
CREATE INDEX remote_requests_tenant_priority_idx
  ON remote_requests (tenant_id, priority DESC, requested_at, request_id);
CREATE INDEX remote_leases_tenant_expiry_idx
  ON remote_leases (tenant_id, expires_at, run_id);
CREATE INDEX remote_workers_tenant_pool_idx
  ON remote_workers (tenant_id, pool, last_heartbeat_at);

DO $rls$
DECLARE table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'remote_requests', 'remote_plans', 'remote_runs', 'remote_workers',
    'remote_leases', 'remote_artifact_manifests', 'remote_containment_reports'
  ]
  LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', table_name);
    EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', table_name);
    EXECUTE format(
      'CREATE POLICY tenant_isolation ON %I USING '
      '(tenant_id = nullif(current_setting(''control_plane.tenant_id'', true), '''')) '
      'WITH CHECK (tenant_id = nullif(current_setting(''control_plane.tenant_id'', true), ''''))',
      table_name
    );
  END LOOP;
END
$rls$;

CREATE FUNCTION scheduler_expired_tenants(reference_time timestamptz)
RETURNS TABLE (tenant_id text)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, control_plane
AS $function$
  SELECT DISTINCT lease.tenant_id
  FROM control_plane.remote_leases AS lease
  WHERE lease.expires_at <= reference_time
  ORDER BY lease.tenant_id
$function$;

CREATE FUNCTION scheduler_queued_tenants()
RETURNS TABLE (tenant_id text)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, control_plane
AS $function$
  SELECT DISTINCT run.tenant_id
  FROM control_plane.remote_runs AS run
  WHERE run.state = 'queued'
  ORDER BY run.tenant_id
$function$;

REVOKE ALL ON FUNCTION scheduler_expired_tenants(timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION scheduler_queued_tenants() FROM PUBLIC;
