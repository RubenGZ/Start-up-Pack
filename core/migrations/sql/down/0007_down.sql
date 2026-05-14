-- 0007_down.sql — Reverso de 0007_billing
-- Elimina billing_events e invoices

DROP TABLE IF EXISTS invoices CASCADE;
DROP TABLE IF EXISTS billing_events CASCADE;
