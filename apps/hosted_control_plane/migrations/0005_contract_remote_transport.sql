SET search_path = control_plane, pg_catalog;

ALTER TABLE remote_artifact_manifests
  ALTER COLUMN interactive_transport SET NOT NULL;
