SET search_path = devex_hosted, pg_catalog;

-- Contract phase for v1. It is intentionally idempotent and is only promoted
-- after every application instance writes the expanded shape.
ALTER TABLE workspace_revisions ALTER COLUMN document SET NOT NULL;
ALTER TABLE collaboration_events ALTER COLUMN payload SET NOT NULL;
ALTER TABLE idempotency ALTER COLUMN response_document SET NOT NULL;
