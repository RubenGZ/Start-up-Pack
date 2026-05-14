-- 0005_down.sql — Reverso de 0005_auth
-- Elimina sesiones, magic links y funciones de auth

DROP FUNCTION IF EXISTS verify_magic_link(TEXT) CASCADE;
DROP FUNCTION IF EXISTS create_magic_link(CITEXT) CASCADE;
DROP FUNCTION IF EXISTS create_session(UUID, INET, TEXT) CASCADE;
DROP FUNCTION IF EXISTS verify_session(TEXT) CASCADE;
DROP FUNCTION IF EXISTS revoke_session(TEXT) CASCADE;
DROP FUNCTION IF EXISTS cleanup_expired_auth() CASCADE;
DROP TABLE IF EXISTS magic_links CASCADE;
DROP TABLE IF EXISTS sessions CASCADE;
