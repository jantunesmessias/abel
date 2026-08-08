#!/usr/bin/env bash
set -euo pipefail

: "${DEVEX_DATABASE_URL:?DEVEX_DATABASE_URL is required}"
rls_role="${DEVEX_RLS_ROLE:-devex_app}"
if [[ ! "$rls_role" =~ ^[a-z_][a-z0-9_]{0,62}$ ]]; then
  echo 'DEVEX_RLS_ROLE is not a safe PostgreSQL role identifier.' >&2
  exit 64
fi
psql_command="${DEVEX_PSQL:-psql}"
command -v "$psql_command" >/dev/null 2>&1 || {
  echo 'psql is unavailable.' >&2
  exit 69
}

suffix="${BASHPID:-$$}"
"$psql_command" "$DEVEX_DATABASE_URL" \
  --set=ON_ERROR_STOP=1 \
  --set=rls_role="$rls_role" \
  --set=suffix="$suffix" <<'SQL'
SELECT set_config('devex.rehearsal_role', :'rls_role', false);
SELECT set_config('devex.rehearsal_suffix', :'suffix', false);

DO $verify_role$
DECLARE bypass boolean;
DECLARE superuser boolean;
BEGIN
  SELECT rolbypassrls, rolsuper
    INTO bypass, superuser
    FROM pg_roles
    WHERE rolname = current_setting('devex.rehearsal_role');
  IF NOT FOUND OR bypass OR superuser THEN
    RAISE EXCEPTION 'RLS test role must exist, be NOBYPASSRLS, and non-superuser';
  END IF;
END
$verify_role$;

DO $verify_catalog$
DECLARE tenant_tables integer;
DECLARE protected_tables integer;
DECLARE policy_tables integer;
BEGIN
  SELECT count(DISTINCT table_name)
    INTO tenant_tables
    FROM information_schema.columns
    WHERE table_schema = 'devex_hosted' AND column_name = 'tenant_id';
  SELECT count(*)
    INTO protected_tables
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'devex_hosted'
      AND c.relkind = 'r'
      AND c.relrowsecurity
      AND c.relforcerowsecurity;
  SELECT count(DISTINCT tablename)
    INTO policy_tables
    FROM pg_policies
    WHERE schemaname = 'devex_hosted' AND policyname = 'tenant_isolation';
  IF tenant_tables < 1 OR protected_tables <> tenant_tables OR policy_tables <> tenant_tables THEN
    RAISE EXCEPTION 'RLS coverage mismatch: tenant=%, protected=%, policy=%',
      tenant_tables, protected_tables, policy_tables;
  END IF;
END
$verify_catalog$;

BEGIN;
SET LOCAL row_security = off;
INSERT INTO devex_hosted.organizations (
  tenant_id, slug, display_name, created_at
) VALUES
  ('rls-a-' || :'suffix', 'rlsa' || :'suffix', 'RLS tenant A', clock_timestamp()),
  ('rls-b-' || :'suffix', 'rlsb' || :'suffix', 'RLS tenant B', clock_timestamp());
GRANT USAGE ON SCHEMA devex_hosted TO :"rls_role";
GRANT SELECT, INSERT ON devex_hosted.organizations TO :"rls_role";
SET LOCAL ROLE :"rls_role";
SET LOCAL row_security = on;

SELECT set_config('devex.tenant_id', 'rls-a-' || :'suffix', true);
DO $tenant_a$
DECLARE visible integer;
DECLARE blocked boolean := false;
BEGIN
  SELECT count(*) INTO visible FROM devex_hosted.organizations;
  IF visible <> 1 THEN
    RAISE EXCEPTION 'tenant A observed % organization rows', visible;
  END IF;
  BEGIN
    INSERT INTO devex_hosted.organizations (
      tenant_id, slug, display_name, created_at
    ) VALUES (
      'rls-cross-' || current_setting('devex.rehearsal_suffix'),
      'rlsx' || current_setting('devex.rehearsal_suffix'),
      'cross tenant write',
      clock_timestamp()
    );
  EXCEPTION WHEN insufficient_privilege THEN
    blocked := true;
  END;
  IF NOT blocked THEN
    RAISE EXCEPTION 'cross-tenant INSERT was not blocked by RLS';
  END IF;
END
$tenant_a$;

SELECT set_config('devex.tenant_id', '', true);
DO $without_context$
DECLARE visible integer;
BEGIN
  SELECT count(*) INTO visible FROM devex_hosted.organizations;
  IF visible <> 0 THEN
    RAISE EXCEPTION 'missing tenant context exposed % organization rows', visible;
  END IF;
END
$without_context$;

SELECT set_config('devex.tenant_id', 'rls-b-' || :'suffix', true);
DO $tenant_b$
DECLARE visible integer;
BEGIN
  SELECT count(*) INTO visible FROM devex_hosted.organizations;
  IF visible <> 1 THEN
    RAISE EXCEPTION 'tenant B observed % organization rows', visible;
  END IF;
END
$tenant_b$;
ROLLBACK;
SQL

echo 'PostgreSQL RLS verified for catalog coverage, isolation, no-context denial, and cross-tenant writes.'
