-- 0016_down.sql — Reverso de 0016_stripe_webhooks
-- Elimina processor de webhooks Stripe

DROP FUNCTION IF EXISTS process_billing_event(TEXT, JSONB, TEXT) CASCADE;
DROP FUNCTION IF EXISTS _handle_invoice_payment_failed(JSONB) CASCADE;
DROP FUNCTION IF EXISTS _handle_invoice_paid(JSONB) CASCADE;
DROP FUNCTION IF EXISTS _handle_subscription_deleted(JSONB) CASCADE;
DROP FUNCTION IF EXISTS _handle_subscription_upsert(JSONB, TEXT) CASCADE;
DROP FUNCTION IF EXISTS _stripe_status_from_payload(JSONB) CASCADE;
DROP FUNCTION IF EXISTS _stripe_plan_from_payload(JSONB) CASCADE;
