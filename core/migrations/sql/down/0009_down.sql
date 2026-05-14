-- 0009_down.sql — Reverso de 0009_health
-- Elimina health check

DROP VIEW IF EXISTS health_status CASCADE;
DROP FUNCTION IF EXISTS health_check() CASCADE;
