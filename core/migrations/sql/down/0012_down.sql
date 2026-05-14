-- 0012_down.sql — Reverso de 0012_audit
-- Elimina audit log y trigger universal

DROP FUNCTION IF EXISTS apply_audit_trigger(TEXT) CASCADE;
DROP FUNCTION IF EXISTS audit_trigger_fn() CASCADE;
DROP TABLE IF EXISTS audit_log CASCADE;
