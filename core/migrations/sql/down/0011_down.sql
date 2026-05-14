-- 0011_down.sql — Reverso de 0011_rate_limit
-- Elimina rate limiting

DROP FUNCTION IF EXISTS check_rate_limit(UUID, TEXT, TEXT) CASCADE;
DROP TABLE IF EXISTS rate_limit_counters CASCADE;
DROP TABLE IF EXISTS rate_limit_config CASCADE;
