SET search_path = control_plane, pg_catalog;

ALTER TABLE remote_artifact_manifests
  ADD COLUMN interactive_transport text;

ALTER TABLE remote_artifact_manifests
  ADD CONSTRAINT remote_artifact_manifests_transport_check CHECK (
    interactive_transport IN (
      'webDirect', 'scrcpyH264Control', 'periodicScreenshotReadOnly', 'none'
    )
  ) NOT VALID;

UPDATE remote_artifact_manifests
SET interactive_transport = COALESCE(
      document ->> 'interactiveTransport',
      'none'
    ),
    document = CASE
      WHEN document ? 'interactiveTransport' THEN document
      ELSE document || '{"interactiveTransport":"none"}'::jsonb
    END
WHERE interactive_transport IS NULL;

ALTER TABLE remote_artifact_manifests
  VALIDATE CONSTRAINT remote_artifact_manifests_transport_check;
