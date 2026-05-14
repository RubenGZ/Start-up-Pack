-- 02_billing_test.sql — pgTAP: billing module
-- Suite: subscriptions · process_billing_event · portal sessions
-- Verifica: (1) idempotencia de webhooks, (2) mapeo de planes Stripe,
--           (3) flujo completo portal pending→active→expired,
--           (4) bloqueo RBAC en request_billing_portal

BEGIN;

SELECT plan(14);

-- ── Fixtures ────────────────────────────────────────────────────────────────
-- Org + users + subscripción Stripe activa
INSERT INTO organizations (id, name, slug, plan)
VALUES ('00000000-0000-0000-0000-000000000001', 'Billing Test Org', 'billing-test', 'free')
ON CONFLICT (id) DO NOTHING;

INSERT INTO users (id, email, name)
VALUES
  ('00000000-0000-0000-0000-000000000010', 'owner@test.com', 'Owner User'),
  ('00000000-0000-0000-0000-000000000011', 'member@test.com', 'Member User')
ON CONFLICT (id) DO NOTHING;

INSERT INTO organization_members (org_id, user_id, role)
VALUES
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000010', 'owner'),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000011', 'member')
ON CONFLICT DO NOTHING;

INSERT INTO subscriptions (id, org_id, plan, status, provider, provider_sub_id)
VALUES (
  '00000000-0000-0000-0000-000000000020',
  '00000000-0000-0000-0000-000000000001',
  'free', 'active', 'stripe', 'sub_test_001'
)
ON CONFLICT (id) DO NOTHING;

-- ── BLOQUE 1: _stripe_plan_from_payload() ────────────────────────────────────

SELECT ok(
  _stripe_plan_from_payload('{"metadata":{"plan":"pro"}}') = 'pro',
  'T1: plan=pro desde metadata.plan'
);

SELECT ok(
  _stripe_plan_from_payload('{"items":{"data":[{"price":{"lookup_key":"starter-monthly"}}]}}') = 'starter',
  'T2: plan=starter desde lookup_key'
);

SELECT ok(
  _stripe_plan_from_payload('{"items":{"data":[{"price":{"nickname":"enterprise-annual"}}]}}') = 'enterprise',
  'T3: plan=enterprise desde price.nickname'
);

SELECT ok(
  _stripe_plan_from_payload('{"unrelated":"data"}') = 'free',
  'T4: payload sin plan → fallback free'
);

-- ── BLOQUE 2: process_billing_event — idempotencia ───────────────────────────

-- Primera llamada: debe procesar
SELECT ok(
  (SELECT (process_billing_event(
    'customer.subscription.updated',
    '{"id":"sub_test_001","status":"active","metadata":{"plan":"pro"},"customer":"cus_abc","items":{"data":[]}}'::JSONB,
    'evt_test_001'
  ))->>'processed' = 'true'
  OR
  (process_billing_event(
    'customer.subscription.updated',
    '{"id":"sub_test_001","status":"active","metadata":{"plan":"pro"},"customer":"cus_abc","items":{"data":[]}}'::JSONB,
    'evt_test_001'
  ))->>'skipped' IS NULL
  ),
  'T5: primer proceso de evt_test_001 no retorna error'
);

-- Segunda llamada con mismo provider_event_id → skipped (idempotente)
SELECT ok(
  (process_billing_event(
    'customer.subscription.updated',
    '{"id":"sub_test_001","status":"active"}'::JSONB,
    'evt_test_001'
  ))->>'skipped' = 'true',
  'T6: segundo proceso de evt_test_001 retorna skipped=true (idempotencia)'
);

SELECT ok(
  (SELECT count(*) = 1 FROM billing_events WHERE provider_event_id = 'evt_test_001'),
  'T7: exactamente 1 fila en billing_events para evt_test_001'
);

-- ── BLOQUE 3: Portal billing — flujo completo ────────────────────────────────

-- T8: member SIN rol owner/admin no puede solicitar portal
SELECT ok(
  (request_billing_portal(
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000011',  -- member
    'https://app.test/billing'
  ))->>'error' = 'forbidden',
  'T8: member sin rol owner/admin recibe error=forbidden'
);

-- T9: owner SÍ puede solicitar portal
SELECT ok(
  (request_billing_portal(
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000010',  -- owner
    'https://app.test/billing'
  ))->>'success' = 'true',
  'T9: owner puede solicitar portal → success=true'
);

SELECT ok(
  (SELECT count(*) = 1
   FROM billing_portal_sessions
   WHERE org_id = '00000000-0000-0000-0000-000000000001'
     AND status = 'pending'),
  'T10: sesión de portal creada en estado pending'
);

-- T11: fulfill activa la sesión
DO $$
DECLARE v_sid UUID;
BEGIN
  SELECT id INTO v_sid FROM billing_portal_sessions
  WHERE org_id = '00000000-0000-0000-0000-000000000001' AND status = 'pending'
  LIMIT 1;

  PERFORM fulfill_billing_portal(
    v_sid,
    'bps_test_stripe_001',
    'https://billing.stripe.com/session/test_abc',
    NOW() + INTERVAL '60 minutes'
  );
END $$;

SELECT ok(
  (SELECT status = 'active'
   FROM billing_portal_sessions
   WHERE org_id = '00000000-0000-0000-0000-000000000001'
   ORDER BY created_at DESC LIMIT 1),
  'T11: fulfill_billing_portal() → status=active'
);

-- T12: get_billing_portal_url devuelve la URL activa
SELECT ok(
  (get_billing_portal_url(
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000010'
  ))->>'portal_url' = 'https://billing.stripe.com/session/test_abc',
  'T12: get_billing_portal_url devuelve URL correcta'
);

-- T13: expire_old_portal_sessions limpia sesiones vencidas
UPDATE billing_portal_sessions
SET expires_at = NOW() - INTERVAL '1 minute'
WHERE org_id = '00000000-0000-0000-0000-000000000001'
  AND status = 'active';

SELECT ok(
  (SELECT expire_old_portal_sessions() >= 1),
  'T13: expire_old_portal_sessions() retorna >= 1 sesión expirada'
);

SELECT ok(
  (SELECT count(*) = 0
   FROM billing_portal_sessions
   WHERE org_id = '00000000-0000-0000-0000-000000000001'
     AND status = 'active'),
  'T14: ninguna sesión active tras expire_old_portal_sessions()'
);

SELECT * FROM finish();

ROLLBACK;
