-- stripe.webhooks.sql — procesador de webhooks Stripe [SUP-12]
-- Eventos: subscription.created/updated/deleted, invoice.paid, invoice.payment_failed

-- Helper: mapea Stripe price/product metadata → plan interno
CREATE OR REPLACE FUNCTION _stripe_plan_from_payload(p_payload JSONB)
RETURNS TEXT LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  v_price_id TEXT;
  v_plan     TEXT;
BEGIN
  -- Intentar leer desde items.data[0].price.lookup_key o metadata.plan
  v_price_id := COALESCE(
    p_payload->'metadata'->>'plan',
    p_payload->'items'->'data'->0->'price'->>'lookup_key',
    p_payload->'items'->'data'->0->'price'->>'nickname',
    p_payload->'plan'->>'nickname'
  );

  v_plan := CASE
    WHEN v_price_id ILIKE '%enterprise%' THEN 'enterprise'
    WHEN v_price_id ILIKE '%pro%'        THEN 'pro'
    WHEN v_price_id ILIKE '%starter%'    THEN 'starter'
    ELSE 'free'
  END;

  RETURN v_plan;
END;
$$;

-- Helper: mapea Stripe subscription status → status interno
CREATE OR REPLACE FUNCTION _stripe_status_from_payload(p_status TEXT)
RETURNS TEXT LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  RETURN CASE p_status
    WHEN 'active'            THEN 'active'
    WHEN 'trialing'          THEN 'trialing'
    WHEN 'past_due'          THEN 'past_due'
    WHEN 'canceled'          THEN 'canceled'
    WHEN 'incomplete'        THEN 'past_due'
    WHEN 'incomplete_expired'THEN 'canceled'
    ELSE 'active'
  END;
END;
$$;

-- 1. process_billing_event — entrada principal de webhooks
CREATE OR REPLACE FUNCTION process_billing_event(
  p_event_type       TEXT,
  p_payload          JSONB,
  p_provider_event_id TEXT DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_event_id UUID;
  v_org_id   UUID;
  v_result   JSONB;
BEGIN
  -- Idempotencia: skip si ya procesamos este evento Stripe
  IF p_provider_event_id IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM billing_events
      WHERE provider_event_id = p_provider_event_id AND processed = TRUE
    ) THEN
      RETURN jsonb_build_object('status', 'already_processed', 'event', p_provider_event_id);
    END IF;
  END IF;

  -- Resolver org_id desde provider_sub_id (subscriptions) o provider_invoice_id (invoices)
  SELECT org_id INTO v_org_id
  FROM subscriptions
  WHERE provider_sub_id = COALESCE(
    p_payload->>'id',                       -- subscription events
    p_payload->>'subscription'              -- invoice events
  )
  LIMIT 1;

  -- Registrar el evento (ON CONFLICT por idempotencia)
  INSERT INTO billing_events (org_id, event_type, provider_event_id, payload)
  VALUES (v_org_id, p_event_type, p_provider_event_id, p_payload)
  ON CONFLICT (provider_event_id) DO UPDATE
    SET payload = EXCLUDED.payload
  RETURNING id INTO v_event_id;

  -- Dispatch por tipo de evento
  v_result := CASE
    WHEN p_event_type = 'customer.subscription.created' THEN
      _handle_subscription_upsert(p_payload, v_org_id)
    WHEN p_event_type = 'customer.subscription.updated' THEN
      _handle_subscription_upsert(p_payload, v_org_id)
    WHEN p_event_type = 'customer.subscription.deleted' THEN
      _handle_subscription_deleted(p_payload)
    WHEN p_event_type = 'invoice.paid' THEN
      _handle_invoice_paid(p_payload, v_org_id)
    WHEN p_event_type = 'invoice.payment_failed' THEN
      _handle_invoice_payment_failed(p_payload)
    ELSE
      jsonb_build_object('status', 'ignored', 'event_type', p_event_type)
  END;

  -- Marcar como procesado
  UPDATE billing_events
  SET processed = TRUE, processed_at = NOW()
  WHERE id = v_event_id;

  RETURN jsonb_build_object(
    'event_id',    v_event_id,
    'event_type',  p_event_type,
    'org_id',      v_org_id,
    'result',      v_result
  );
END;
$$;

-- 2. _handle_subscription_upsert — created + updated
CREATE OR REPLACE FUNCTION _handle_subscription_upsert(
  p_payload JSONB,
  p_org_id  UUID
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_sub_id       TEXT := p_payload->>'id';
  v_status       TEXT := _stripe_status_from_payload(p_payload->>'status');
  v_plan         TEXT := _stripe_plan_from_payload(p_payload);
  v_period_start TIMESTAMPTZ := to_timestamp((p_payload->>'current_period_start')::BIGINT);
  v_period_end   TIMESTAMPTZ := to_timestamp((p_payload->>'current_period_end')::BIGINT);
  v_row_id       UUID;
BEGIN
  IF p_org_id IS NULL THEN
    RETURN jsonb_build_object('error', 'org_not_found', 'provider_sub_id', v_sub_id);
  END IF;

  INSERT INTO subscriptions (
    org_id, plan, status, provider, provider_sub_id,
    current_period_start, current_period_end
  ) VALUES (
    p_org_id, v_plan, v_status, 'stripe', v_sub_id,
    v_period_start, v_period_end
  )
  ON CONFLICT (provider_sub_id) DO UPDATE SET
    plan                 = EXCLUDED.plan,
    status               = EXCLUDED.status,
    current_period_start = EXCLUDED.current_period_start,
    current_period_end   = EXCLUDED.current_period_end,
    canceled_at          = CASE WHEN EXCLUDED.status = 'canceled' THEN NOW() ELSE NULL END,
    updated_at           = NOW()
  RETURNING id INTO v_row_id;

  -- Sincronizar plan en organizations
  UPDATE organizations SET plan = v_plan WHERE id = p_org_id;

  RETURN jsonb_build_object(
    'status',          'upserted',
    'subscription_id', v_row_id,
    'plan',            v_plan,
    'sub_status',      v_status
  );
END;
$$;

-- 3. _handle_subscription_deleted — cancela suscripción
CREATE OR REPLACE FUNCTION _handle_subscription_deleted(p_payload JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_sub_id TEXT := p_payload->>'id';
  v_org_id UUID;
BEGIN
  UPDATE subscriptions
  SET status = 'canceled', canceled_at = NOW(), updated_at = NOW()
  WHERE provider_sub_id = v_sub_id
  RETURNING org_id INTO v_org_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'subscription_not_found', 'provider_sub_id', v_sub_id);
  END IF;

  -- Degradar org a free
  UPDATE organizations SET plan = 'free' WHERE id = v_org_id;

  RETURN jsonb_build_object('status', 'canceled', 'provider_sub_id', v_sub_id, 'org_id', v_org_id);
END;
$$;

-- 4. _handle_invoice_paid — registra factura pagada
CREATE OR REPLACE FUNCTION _handle_invoice_paid(p_payload JSONB, p_org_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_inv_id  UUID;
  v_sub_row subscriptions%ROWTYPE;
BEGIN
  SELECT * INTO v_sub_row
  FROM subscriptions
  WHERE provider_sub_id = p_payload->>'subscription'
  LIMIT 1;

  INSERT INTO invoices (
    org_id, subscription_id, provider_invoice_id,
    amount_cents, currency, status, paid_at
  ) VALUES (
    COALESCE(p_org_id, v_sub_row.org_id),
    v_sub_row.id,
    p_payload->>'id',
    (p_payload->>'amount_paid')::INTEGER,
    COALESCE(p_payload->>'currency', 'usd'),
    'paid',
    NOW()
  )
  ON CONFLICT (provider_invoice_id) DO UPDATE SET
    status  = 'paid',
    paid_at = NOW()
  RETURNING id INTO v_inv_id;

  -- Reactivar si estaba past_due
  IF v_sub_row.status = 'past_due' THEN
    UPDATE subscriptions SET status = 'active', updated_at = NOW()
    WHERE id = v_sub_row.id;
  END IF;

  RETURN jsonb_build_object('status', 'invoice_recorded', 'invoice_id', v_inv_id);
END;
$$;

-- 5. _handle_invoice_payment_failed — marca past_due
CREATE OR REPLACE FUNCTION _handle_invoice_payment_failed(p_payload JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_provider_sub_id TEXT := p_payload->>'subscription';
BEGIN
  UPDATE subscriptions
  SET status = 'past_due', updated_at = NOW()
  WHERE provider_sub_id = v_provider_sub_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'subscription_not_found');
  END IF;

  RETURN jsonb_build_object('status', 'marked_past_due', 'provider_sub_id', v_provider_sub_id);
END;
$$;
