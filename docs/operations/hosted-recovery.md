# Hosted recovery runbook

Status: normative for V4 operations. The local rehearsal validates logical
backup integrity, schema restoration, RLS coverage and the elapsed recovery
window. Production RPO additionally depends on continuous PostgreSQL WAL/PITR
and object-storage versioning; a recent `pg_dump` alone is not a PITR strategy.

## Objectives and ownership

- PostgreSQL RPO: at most 15 minutes. Continuously archive WAL to an encrypted,
  access-separated repository and alert when the last successfully archived WAL
  is older than 10 minutes.
- Hosted service RTO: at most 4 hours, measured from incident declaration until
  the restored API passes migrations, RLS, object inventory and smoke checks.
- Object storage: enable versioning, server-side encryption, retention policy
  and daily inventory for `tenants/<tenant>/blobs/sha256/<digest>` keys.
- The incident commander selects the recovery point. A database operator
  restores PostgreSQL; a storage operator restores object versions; a security
  reviewer validates tenant isolation before traffic is enabled.

Never rehearse into the production database. The supplied script creates a
uniquely named database, validates its exact prefix before deletion, and removes
it on exit.

## Logical rehearsal

Use credentials with `pg_dump` access for the backup and database-create/drop
authority only in the isolated rehearsal environment. `devex_app` must exist as
a non-superuser `NOBYPASSRLS` role.

```bash
export DEVEX_DATABASE_URL='postgresql://backup-user:REDACTED@db.example/devex'
export DEVEX_BACKUP_DIRECTORY=/secure/rehearsal
./tool/hosted/backup_postgres.sh

export PGHOST=rehearsal-db.example
export PGPORT=5432
export PGUSER=rehearsal-admin
export PGPASSWORD='REDACTED'
export DEVEX_BACKUP_FILE=/secure/rehearsal/devex-hosted-YYYYMMDDTHHMMSSZ.dump
./tool/hosted/restore_rehearsal.sh
```

The gate fails when the checksum differs, the backup is older than 900 seconds,
restore exceeds 14,400 seconds, any `tenant_id` table lacks forced RLS/policy,
a tenant sees another tenant, a request without tenant context sees rows, or a
cross-tenant insert succeeds. Secrets must be injected by the operator's secret
manager and must never be copied into evidence artifacts.

## Production PITR exercise

Quarterly, restore the latest base backup and WAL into an isolated network at a
declared timestamp. Record incident start, target recovery timestamp, last
archived WAL, database-ready time, application-ready time and RLS/object checks.
Run migrations only after the restored version is identified. Compare every
`hosted_blobs.object_key`, digest and size to the versioned object inventory;
missing or mismatched bytes keep the service closed.

Bring up the Helm release with digest-pinned images, ingress disabled and
NetworkPolicy active. Run API smoke tests with two distinct OIDC principals and
tenants, replay collaboration events from a saved cursor, and verify that the
offline local core and `.devexbundle` verification remain independent. Enable
traffic only after all checks pass and preserve the timestamped evidence outside
the recovered system.

## Failure and rollback

If integrity, RLS, object reconciliation or the selected recovery point fails,
destroy only the isolated restore, select an earlier valid recovery point and
repeat. Do not mutate the damaged source or overwrite versioned objects. If the
four-hour window is at risk, escalate the incident; never weaken RLS, digest
checks, TLS or tenant scoping to reduce recovery time.
