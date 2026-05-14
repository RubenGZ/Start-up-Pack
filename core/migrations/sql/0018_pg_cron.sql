-- 0018_pg_cron — scheduler automático de cleanups [SUP-14]
-- Requiere: pg_cron extension instalada en el servidor PostgreSQL
-- En RDS/Supabase: habilitar pg_cron desde dashboard antes de correr esta migration

-- 1. Instalar extensión (safe: no falla si ya existe)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- 2. Limpiar jobs previos si existen (idempotente)
SELECT cron.unschedule(jobid)
FROM cron.job
WHERE command IN (
  'SELECT run_all_cleanups();',
  'SELECT cleanup_expired_invites();'
)
AND jobname IS NOT NULL;

-- 3. Cleanup principal — cada hora (rate_limit + auth expirada)
SELECT cron.schedule(
  'hydra-cleanup-hourly',
  '0 * * * *',
  'SELECT run_all_cleanups();'
);

-- 4. Cleanup invitaciones expiradas — cada día a las 3am
CREATE OR REPLACE FUNCTION cleanup_expired_invites()
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_deleted INT;
BEGIN
  DELETE FROM member_invites
  WHERE accepted = FALSE AND expires_at < NOW();
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

SELECT cron.schedule(
  'hydra-invites-daily',
  '0 3 * * *',
  'SELECT cleanup_expired_invites();'
);

-- 5. Cleanup audit_log > 90 días — cada domingo a las 2am
CREATE OR REPLACE FUNCTION cleanup_old_audit_logs(p_keep_days INT DEFAULT 90)
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_deleted INT;
BEGIN
  DELETE FROM audit_log WHERE created_at < NOW() - (p_keep_days * INTERVAL '1 day');
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RAISE NOTICE '[audit] Cleanup: % filas eliminadas (> %d días)', v_deleted, p_keep_days;
  RETURN v_deleted;
END;
$$;

SELECT cron.schedule(
  'hydra-audit-weekly',
  '0 2 * * 0',
  'SELECT cleanup_old_audit_logs(90);'
);

-- 6. Vista de jobs activos (diagnóstico rápido)
-- SELECT * FROM cron.job;

COMMENT ON FUNCTION cleanup_expired_invites() IS
  'Elimina member_invites no aceptadas y expiradas. Scheduled: 0 3 * * * via pg_cron.';

COMMENT ON FUNCTION cleanup_old_audit_logs(INT) IS
  'Elimina filas de audit_log más antiguas que p_keep_days. Scheduled: 0 2 * * 0 via pg_cron.';
