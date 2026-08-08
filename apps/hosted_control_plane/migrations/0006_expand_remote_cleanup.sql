SET search_path = devex_hosted, pg_catalog;

CREATE TABLE remote_cleanup_tasks (
  tenant_id text NOT NULL,
  run_id text NOT NULL,
  generation integer NOT NULL,
  requested_at timestamptz NOT NULL,
  available_at timestamptz NOT NULL,
  attempts integer NOT NULL DEFAULT 0,
  last_failure_code text,
  PRIMARY KEY (tenant_id, run_id, generation),
  CONSTRAINT remote_cleanup_tasks_run_fk FOREIGN KEY (tenant_id, run_id)
    REFERENCES remote_runs (tenant_id, run_id) ON DELETE CASCADE,
  CONSTRAINT remote_cleanup_tasks_generation_check
    CHECK (generation BETWEEN 1 AND 10),
  CONSTRAINT remote_cleanup_tasks_attempts_check
    CHECK (attempts BETWEEN 0 AND 1000000),
  CONSTRAINT remote_cleanup_tasks_time_check
    CHECK (available_at >= requested_at),
  CONSTRAINT remote_cleanup_tasks_failure_check
    CHECK (
      last_failure_code IS NULL OR
      last_failure_code ~ '^[a-z0-9_]{1,64}$'
    )
);

CREATE INDEX remote_cleanup_tasks_ready_idx
  ON remote_cleanup_tasks (available_at, tenant_id, run_id, generation);

ALTER TABLE remote_cleanup_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE remote_cleanup_tasks FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON remote_cleanup_tasks
  USING (
    tenant_id = nullif(current_setting('devex.tenant_id', true), '')
  )
  WITH CHECK (
    tenant_id = nullif(current_setting('devex.tenant_id', true), '')
  );

CREATE OR REPLACE FUNCTION scheduler_queued_tenants()
RETURNS TABLE (tenant_id text)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, devex_hosted
AS $function$
  SELECT DISTINCT run.tenant_id
  FROM devex_hosted.remote_runs AS run
  WHERE run.state = 'queued'
    AND NOT EXISTS (
      SELECT 1
      FROM devex_hosted.remote_cleanup_tasks AS cleanup
      WHERE cleanup.tenant_id = run.tenant_id
        AND cleanup.run_id = run.run_id
    )
  ORDER BY run.tenant_id
$function$;

CREATE FUNCTION scheduler_cleanup_tenants(reference_time timestamptz)
RETURNS TABLE (tenant_id text)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, devex_hosted
AS $function$
  SELECT DISTINCT cleanup.tenant_id
  FROM devex_hosted.remote_cleanup_tasks AS cleanup
  WHERE cleanup.available_at <= reference_time
  ORDER BY cleanup.tenant_id
$function$;

REVOKE ALL ON FUNCTION scheduler_cleanup_tenants(timestamptz) FROM PUBLIC;
