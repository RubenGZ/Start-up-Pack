-- 0018_pg_cron — scheduler automático de cleanups [SUP-14]
-- Resiliente: si pg_cron no está disponible (CI, entornos básicos), continúa sin error.
-- En producción: instalar pg_cron y activar shared_preload_libraries=pg_cron primero.

-- Funciones de cleanup independientes de pg_cron (siempre se crean)
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

COMMENT ON FUNCTION cleanup_expired_invites() IS
  'Elimina member_invites no aceptadas y expiradas. Scheduled: 0 3 * * * via pg_cron.';

COMMENT ON FUNCTION cleanup_old_audit_logs(INT) IS
  'Elimina filas de audit_log más antiguas que p_keep_days. Scheduled: 0 2 * * 0 via pg_cron.';

-- Scheduler pg_cron — se instala solo si el entorno lo soporta
DO $$
BEGIN
  -- Intentar instalar extensión
  CREATE EXTENSION IF NOT EXISTS pg_cron;

  -- Limpiar jobs previos (idempotente)
  PERFORM cron.unschedule(jobid)
  FROM cron.job
  WHERE command IN (
    'SELECT run_all_cleanups();',
    'SELECT cleanup_expired_invites();',
    'SELECT cleanup_old_audit_logs(90);'
  );

  -- Job 1: cleanup principal cada hora
  PERFORM cron.schedule(
    'hydra-cleanup-hourly',
    '0 * * * *',
    'SELECT run_all_cleanups();'
  );

  -- Job 2: invitaciones expiradas cada día 3am
  PERFORM cron.schedule(
    'hydra-invites-daily',
    '0 3 * * *',
    'SELECT cleanup_expired_invites();'
  );

  -- Job 3: audit_log > 90 días cada domingo 2am
  PERFORM cron.schedule(
    'hydra-audit-weekly',
    '0 2 * * 0',
    'SELECT cleanup_old_audit_logs(90);'
  );

  RAISE NOTICE '[pg_cron] 3 jobs programados: hydra-cleanup-hourly, hydra-invites-daily, hydra-audit-weekly';

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[pg_cron] No disponible en este entorno (%). Jobs de cleanup creados pero sin scheduler automático.', SQLERRM;
  RAISE NOTICE '[pg_cron] Para activar: instalar postgresql-XX-cron y añadir shared_preload_libraries=pg_cron';
END
$$;
