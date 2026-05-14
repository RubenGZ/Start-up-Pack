-- 0006_down.sql — Reverso de 0006_oauth
-- Elimina cuentas OAuth

DROP FUNCTION IF EXISTS upsert_oauth_account(UUID, TEXT, TEXT, CITEXT, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ) CASCADE;
DROP TABLE IF EXISTS oauth_accounts CASCADE;
