-- 0013_down.sql — Reverso de 0013_cleanup
-- Elimina funciones de cleanup periódico

DROP FUNCTION IF EXISTS run_all_cleanups() CASCADE;
DROP FUNCTION IF EXISTS cleanup_expired_rate_limits() CASCADE;
DROP FUNCTION IF EXISTS cleanup_expired_auth() CASCADE;
