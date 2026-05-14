-- 0022_down.sql — Reverso de 0022_billing_portal

DROP FUNCTION IF EXISTS expire_old_portal_sessions() CASCADE;
DROP FUNCTION IF EXISTS get_billing_portal_url(UUID, UUID) CASCADE;
DROP FUNCTION IF EXISTS fulfill_billing_portal(UUID, TEXT, TEXT, TIMESTAMPTZ) CASCADE;
DROP FUNCTION IF EXISTS request_billing_portal(UUID, UUID, TEXT) CASCADE;
DROP TABLE IF EXISTS billing_portal_sessions CASCADE;
