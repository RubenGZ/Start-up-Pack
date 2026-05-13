-- 004_schema_versions.sql — registro de migraciones aplicadas

CREATE TABLE IF NOT EXISTS schema_versions (
  id          SERIAL PRIMARY KEY,
  version     TEXT NOT NULL UNIQUE,
  name        TEXT NOT NULL,
  checksum    TEXT NOT NULL,
  applied_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  applied_by  TEXT DEFAULT CURRENT_USER
);

CREATE INDEX IF NOT EXISTS idx_schema_versions_version ON schema_versions(version);
