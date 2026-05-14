-- 0014_down.sql — Reverso de 0014_auth_context
-- Elimina funciones de contexto de sesión

DROP FUNCTION IF EXISTS revoke_all_sessions(UUID) CASCADE;
DROP FUNCTION IF EXISTS set_session_context(UUID, UUID, INET, TEXT) CASCADE;
DROP FUNCTION IF EXISTS complete_signup(CITEXT, TEXT, TEXT, TEXT) CASCADE;
DROP FUNCTION IF EXISTS get_session_context(TEXT) CASCADE;
