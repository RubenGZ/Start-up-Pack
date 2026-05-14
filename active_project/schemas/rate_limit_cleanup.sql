-- rate_limit_cleanup.sql — limpieza de ventanas expiradas [SUP-8 complement]
-- Previene crecimiento ilimitado de rate_limit_counters

-- Función de cleanup: borra filas con window_start más antiguo que p_keep_hours
CREATE OR REPLACE FUNCTION cleanup_rate_limit_counters(p_keep_hours INT DEFAULT 24)
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_deleted INT;
BEGIN
  DELETE FROM rate_limit_counters
  WHERE window_start < NOW() - (p_keep_hours * INTERVAL '1 hour');

  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  RAISE NOTICE '[rate_limit] Cleanup: % filas eliminadas (ventanas > %h)', v_deleted, p_keep_hours;
  RETURN v_deleted;
END;
$$;

-- Función combinada: limpia auth expirada + rate limit counters
-- Invocar vía pg_cron o cron job externo (ej: cada hora)
-- Ejemplo pg_cron: SELECT cron.schedule('0 * * * *', 'SELECT run_all_cleanups()');
CREATE OR REPLACE FUNCTION run_all_cleanups()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_rl_deleted  INT;
  v_auth_deleted INT := 0;
BEGIN
  -- Rate limit counters (ventanas > 24h)
  v_rl_deleted := cleanup_rate_limit_counters(24);

  -- Auth expirada (magic_links + sessions)
  DELETE FROM magic_links WHERE expires_at < NOW();
  GET DIAGNOSTICS v_auth_deleted = ROW_COUNT;
  DELETE FROM sessions WHERE expires_at < NOW();

  RETURN jsonb_build_object(
    'rate_limit_rows_deleted', v_rl_deleted,
    'auth_rows_deleted',       v_auth_deleted,
    'ran_at',                  NOW()
  );
END;
$$;
