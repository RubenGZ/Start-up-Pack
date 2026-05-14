-- 0018_down.sql — Reverso de 0018_pg_cron
-- Elimina jobs y funciones de cleanup automático

DO $$
BEGIN
  PERFORM cron.unschedule(jobid)
  FROM cron.job
  WHERE jobname IN (
    'hydra-cleanup-hourly',
    'hydra-invites-daily',
    'hydra-audit-weekly'
  );
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[pg_cron] No disponible, saltando unschedule';
END $$;

DROP FUNCTION IF EXISTS cleanup_old_audit_logs(INT) CASCADE;
DROP FUNCTION IF EXISTS cleanup_expired_invites() CASCADE;
DROP FUNCTION IF EXISTS run_all_cleanups() CASCADE;
