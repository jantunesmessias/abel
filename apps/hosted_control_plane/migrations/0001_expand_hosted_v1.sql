CREATE SCHEMA IF NOT EXISTS devex_hosted;
SET search_path = devex_hosted, pg_catalog;

CREATE TABLE organizations (
  tenant_id text PRIMARY KEY,
  slug text NOT NULL,
  display_name text NOT NULL,
  created_at timestamptz NOT NULL,
  CONSTRAINT organizations_tenant_slug_unique UNIQUE (tenant_id, slug),
  CONSTRAINT organizations_slug_check CHECK (slug ~ '^[a-z][a-z0-9-]{2,62}$')
);

CREATE TABLE principals (
  tenant_id text NOT NULL,
  principal_id text NOT NULL,
  issuer text NOT NULL,
  subject text NOT NULL,
  display_name text NOT NULL,
  created_at timestamptz NOT NULL,
  PRIMARY KEY (tenant_id, principal_id),
  CONSTRAINT principals_tenant_subject_unique UNIQUE (tenant_id, issuer, subject),
  CONSTRAINT principals_tenant_fk FOREIGN KEY (tenant_id)
    REFERENCES organizations (tenant_id) ON DELETE CASCADE
);

CREATE TABLE memberships (
  tenant_id text NOT NULL,
  principal_id text NOT NULL,
  role text NOT NULL,
  created_at timestamptz NOT NULL,
  PRIMARY KEY (tenant_id, principal_id),
  CONSTRAINT memberships_principal_fk FOREIGN KEY (tenant_id, principal_id)
    REFERENCES principals (tenant_id, principal_id) ON DELETE CASCADE,
  CONSTRAINT memberships_role_check CHECK (role IN ('owner', 'admin', 'editor', 'reviewer', 'viewer'))
);

CREATE TABLE workspaces (
  tenant_id text NOT NULL,
  workspace_id text NOT NULL,
  display_name text NOT NULL,
  created_at timestamptz NOT NULL,
  created_by text NOT NULL,
  PRIMARY KEY (tenant_id, workspace_id),
  CONSTRAINT workspaces_creator_fk FOREIGN KEY (tenant_id, created_by)
    REFERENCES principals (tenant_id, principal_id)
);

CREATE TABLE workspace_revisions (
  tenant_id text NOT NULL,
  workspace_id text NOT NULL,
  revision_id text NOT NULL,
  revision_digest text NOT NULL,
  content_digest text NOT NULL,
  change_set_digest text NOT NULL,
  parent_digest text,
  document jsonb NOT NULL,
  created_at timestamptz NOT NULL,
  created_by text NOT NULL,
  PRIMARY KEY (tenant_id, workspace_id, revision_digest),
  CONSTRAINT workspace_revisions_id_unique UNIQUE (tenant_id, workspace_id, revision_id),
  CONSTRAINT workspace_revisions_workspace_fk FOREIGN KEY (tenant_id, workspace_id)
    REFERENCES workspaces (tenant_id, workspace_id) ON DELETE CASCADE,
  CONSTRAINT workspace_revisions_creator_fk FOREIGN KEY (tenant_id, created_by)
    REFERENCES principals (tenant_id, principal_id),
  CONSTRAINT workspace_revisions_digest_check CHECK (
    revision_digest ~ '^sha256:[0-9a-f]{64}$' AND
    content_digest ~ '^sha256:[0-9a-f]{64}$' AND
    change_set_digest ~ '^sha256:[0-9a-f]{64}$' AND
    (parent_digest IS NULL OR parent_digest ~ '^sha256:[0-9a-f]{64}$')
  )
);

CREATE TABLE workspace_heads (
  tenant_id text NOT NULL,
  workspace_id text NOT NULL,
  revision_digest text NOT NULL,
  updated_at timestamptz NOT NULL,
  PRIMARY KEY (tenant_id, workspace_id),
  CONSTRAINT workspace_heads_revision_fk FOREIGN KEY (tenant_id, workspace_id, revision_digest)
    REFERENCES workspace_revisions (tenant_id, workspace_id, revision_digest)
);

CREATE TABLE hosted_blobs (
  tenant_id text NOT NULL,
  digest text NOT NULL,
  size_bytes bigint NOT NULL,
  media_type text NOT NULL,
  classification text NOT NULL,
  object_key text NOT NULL,
  retention_until timestamptz,
  created_at timestamptz NOT NULL,
  PRIMARY KEY (tenant_id, digest),
  CONSTRAINT hosted_blobs_object_unique UNIQUE (tenant_id, object_key),
  CONSTRAINT hosted_blobs_digest_check CHECK (digest ~ '^sha256:[0-9a-f]{64}$'),
  CONSTRAINT hosted_blobs_size_check CHECK (size_bytes >= 0 AND size_bytes <= 1073741824),
  CONSTRAINT hosted_blobs_classification_check CHECK (classification IN ('public', 'internal', 'sensitive')),
  CONSTRAINT hosted_blobs_object_scope_check CHECK (
    object_key = 'tenants/' || tenant_id || '/blobs/sha256/' || substr(digest, 8)
  )
);

CREATE TABLE evidence (
  tenant_id text NOT NULL,
  workspace_id text NOT NULL,
  evidence_digest text NOT NULL,
  subject_digest text NOT NULL,
  document jsonb NOT NULL,
  created_at timestamptz NOT NULL,
  created_by text NOT NULL,
  PRIMARY KEY (tenant_id, workspace_id, evidence_digest),
  CONSTRAINT evidence_workspace_fk FOREIGN KEY (tenant_id, workspace_id)
    REFERENCES workspaces (tenant_id, workspace_id) ON DELETE CASCADE,
  CONSTRAINT evidence_creator_fk FOREIGN KEY (tenant_id, created_by)
    REFERENCES principals (tenant_id, principal_id)
);

CREATE TABLE releases (
  tenant_id text NOT NULL,
  workspace_id text NOT NULL,
  release_digest text NOT NULL,
  subject_digest text NOT NULL,
  document jsonb NOT NULL,
  created_at timestamptz NOT NULL,
  created_by text NOT NULL,
  PRIMARY KEY (tenant_id, workspace_id, release_digest),
  CONSTRAINT releases_workspace_fk FOREIGN KEY (tenant_id, workspace_id)
    REFERENCES workspaces (tenant_id, workspace_id) ON DELETE CASCADE,
  CONSTRAINT releases_creator_fk FOREIGN KEY (tenant_id, created_by)
    REFERENCES principals (tenant_id, principal_id)
);

CREATE TABLE findings (
  tenant_id text NOT NULL,
  workspace_id text NOT NULL,
  finding_id text NOT NULL,
  subject_digest text NOT NULL,
  severity text NOT NULL,
  document jsonb NOT NULL,
  created_at timestamptz NOT NULL,
  created_by text NOT NULL,
  PRIMARY KEY (tenant_id, workspace_id, finding_id),
  CONSTRAINT findings_workspace_fk FOREIGN KEY (tenant_id, workspace_id)
    REFERENCES workspaces (tenant_id, workspace_id) ON DELETE CASCADE,
  CONSTRAINT findings_creator_fk FOREIGN KEY (tenant_id, created_by)
    REFERENCES principals (tenant_id, principal_id)
);

CREATE TABLE approvals (
  tenant_id text NOT NULL,
  workspace_id text NOT NULL,
  approval_id text NOT NULL,
  subject_digest text NOT NULL,
  approved boolean NOT NULL,
  decided_at timestamptz NOT NULL,
  principal_id text NOT NULL,
  document jsonb NOT NULL,
  PRIMARY KEY (tenant_id, workspace_id, approval_id),
  CONSTRAINT approvals_workspace_fk FOREIGN KEY (tenant_id, workspace_id)
    REFERENCES workspaces (tenant_id, workspace_id) ON DELETE CASCADE,
  CONSTRAINT approvals_principal_fk FOREIGN KEY (tenant_id, principal_id)
    REFERENCES principals (tenant_id, principal_id)
);

CREATE TABLE comments (
  tenant_id text NOT NULL,
  workspace_id text NOT NULL,
  thread_id text NOT NULL,
  subject_digest text NOT NULL,
  document jsonb NOT NULL,
  resolved boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL,
  created_by text NOT NULL,
  PRIMARY KEY (tenant_id, workspace_id, thread_id),
  CONSTRAINT comments_workspace_fk FOREIGN KEY (tenant_id, workspace_id)
    REFERENCES workspaces (tenant_id, workspace_id) ON DELETE CASCADE,
  CONSTRAINT comments_creator_fk FOREIGN KEY (tenant_id, created_by)
    REFERENCES principals (tenant_id, principal_id)
);

CREATE TABLE presence (
  tenant_id text NOT NULL,
  workspace_id text NOT NULL,
  session_id text NOT NULL,
  principal_id text NOT NULL,
  expires_at timestamptz NOT NULL,
  PRIMARY KEY (tenant_id, workspace_id, session_id),
  CONSTRAINT presence_workspace_fk FOREIGN KEY (tenant_id, workspace_id)
    REFERENCES workspaces (tenant_id, workspace_id) ON DELETE CASCADE,
  CONSTRAINT presence_principal_fk FOREIGN KEY (tenant_id, principal_id)
    REFERENCES principals (tenant_id, principal_id) ON DELETE CASCADE
);

CREATE TABLE collaboration_events (
  tenant_id text NOT NULL,
  workspace_id text NOT NULL,
  sequence bigint NOT NULL,
  event_digest text NOT NULL,
  kind text NOT NULL,
  subject_digest text NOT NULL,
  principal_id text NOT NULL,
  occurred_at timestamptz NOT NULL,
  payload jsonb NOT NULL,
  PRIMARY KEY (tenant_id, workspace_id, sequence),
  CONSTRAINT collaboration_events_digest_unique UNIQUE (tenant_id, workspace_id, event_digest),
  CONSTRAINT collaboration_events_workspace_fk FOREIGN KEY (tenant_id, workspace_id)
    REFERENCES workspaces (tenant_id, workspace_id) ON DELETE CASCADE,
  CONSTRAINT collaboration_events_principal_fk FOREIGN KEY (tenant_id, principal_id)
    REFERENCES principals (tenant_id, principal_id)
);

CREATE TABLE audit_events (
  tenant_id text NOT NULL,
  audit_id text NOT NULL,
  principal_id text NOT NULL,
  action text NOT NULL,
  subject_digest text NOT NULL,
  occurred_at timestamptz NOT NULL,
  context jsonb NOT NULL,
  PRIMARY KEY (tenant_id, audit_id),
  CONSTRAINT audit_events_principal_fk FOREIGN KEY (tenant_id, principal_id)
    REFERENCES principals (tenant_id, principal_id)
);

CREATE TABLE outbox (
  tenant_id text NOT NULL,
  outbox_id bigint GENERATED ALWAYS AS IDENTITY,
  workspace_id text NOT NULL,
  event_sequence bigint NOT NULL,
  topic text NOT NULL,
  payload jsonb NOT NULL,
  created_at timestamptz NOT NULL,
  published_at timestamptz,
  PRIMARY KEY (tenant_id, outbox_id),
  CONSTRAINT outbox_event_fk FOREIGN KEY (tenant_id, workspace_id, event_sequence)
    REFERENCES collaboration_events (tenant_id, workspace_id, sequence) ON DELETE CASCADE
);

CREATE TABLE idempotency (
  tenant_id text NOT NULL,
  principal_id text NOT NULL,
  idempotency_key text NOT NULL,
  request_digest text NOT NULL,
  response_digest text NOT NULL,
  response_document jsonb NOT NULL,
  created_at timestamptz NOT NULL,
  expires_at timestamptz NOT NULL,
  PRIMARY KEY (tenant_id, principal_id, idempotency_key),
  CONSTRAINT idempotency_principal_fk FOREIGN KEY (tenant_id, principal_id)
    REFERENCES principals (tenant_id, principal_id) ON DELETE CASCADE,
  CONSTRAINT idempotency_expiry_check CHECK (expires_at > created_at)
);

CREATE INDEX presence_tenant_expiry_idx
  ON presence (tenant_id, expires_at, workspace_id);
CREATE INDEX collaboration_events_tenant_cursor_idx
  ON collaboration_events (tenant_id, workspace_id, sequence);
CREATE INDEX outbox_tenant_pending_idx
  ON outbox (tenant_id, published_at, outbox_id);
CREATE INDEX audit_events_tenant_time_idx
  ON audit_events (tenant_id, occurred_at DESC);
CREATE INDEX hosted_blobs_tenant_retention_idx
  ON hosted_blobs (tenant_id, retention_until);

DO $rls$
DECLARE table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'organizations', 'principals', 'memberships', 'workspaces',
    'workspace_revisions', 'workspace_heads', 'hosted_blobs', 'evidence',
    'releases', 'findings', 'approvals', 'comments', 'presence',
    'collaboration_events', 'audit_events', 'outbox', 'idempotency'
  ]
  LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', table_name);
    EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', table_name);
    EXECUTE format(
      'CREATE POLICY tenant_isolation ON %I USING '
      '(tenant_id = nullif(current_setting(''devex.tenant_id'', true), '''')) '
      'WITH CHECK (tenant_id = nullif(current_setting(''devex.tenant_id'', true), ''''))',
      table_name
    );
  END LOOP;
END
$rls$;
