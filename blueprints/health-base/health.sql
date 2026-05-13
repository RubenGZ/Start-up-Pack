-- health.sql — endpoint /health para cualquier startup Hydra

CREATE OR REPLACE FUNCTION health_check()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_db_name        TEXT;
  v_pg_version     TEXT;
  v_last_migration RECORD;
  v_active_conns   INT;
  v_max_conns      INT;
  v_extensions     JSONB;
BEGIN
  SELECT current_database() INTO v_db_name;
  SELECT version()          INTO v_pg_version;

  SELECT count(*) INTO v_active_conns
  FROM pg_stat_activity
  WHERE state = 'active';

  SELECT setting::INT INTO v_max_conns
  FROM pg_settings WHERE name = 'max_connections';

  SELECT jsonb_agg(jsonb_build_object('name', extname, 'version', extversion))
  INTO v_extensions
  FROM pg_extension
  WHERE extname != 'plpgsql';

  SELECT version, name, applied_at
  INTO v_last_migration
  FROM schema_versions
  ORDER BY applied_at DESC
  LIMIT 1;

  RETURN jsonb_build_object(
    'status',    'ok',
    'database',  v_db_name,
    'pg_version', split_part(v_pg_version, ',', 1),
    'connections', jsonb_build_object(
      'active', v_active_conns,
      'max',    v_max_conns,
      'usage_pct', round((v_active_conns::NUMERIC / v_max_conns) * 100, 1)
    ),
    'extensions', COALESCE(v_extensions, '[]'::JSONB),
    'last_migration', CASE
      WHEN v_last_migration IS NULL THEN NULL
      ELSE jsonb_build_object(
        'version',    v_last_migration.version,
        'name',       v_last_migration.name,
        'applied_at', v_last_migration.applied_at
      )
    END,
    'checked_at', now()
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'status', 'error',
    'detail', SQLERRM,
    'checked_at', now()
  );
END;
$$;

-- View para queries directas sin llamar la función
CREATE OR REPLACE VIEW health_status AS
SELECT health_check() AS result;

COMMENT ON FUNCTION health_check() IS 'Returns DB health: connections, extensions, last migration. Safe to expose via API.';
