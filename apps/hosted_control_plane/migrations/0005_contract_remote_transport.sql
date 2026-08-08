SET search_path = devex_hosted, pg_catalog;

ALTER TABLE remote_artifact_manifests
  ALTER COLUMN interactive_transport SET NOT NULL;
