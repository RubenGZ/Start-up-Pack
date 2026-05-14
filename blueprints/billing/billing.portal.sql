-- billing.portal.sql — Stripe Customer Portal integration [SUP-21]
-- Gestiona sesiones de portal de autoservicio Stripe
-- El worker externo llama a Stripe API y usa estas funciones para persistir estado

-- 1. Tabla de sesiones de portal
CREATE TABLE IF NOT EXISTS billing_portal_sessions (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  org_id          UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  requested_by    UUID NOT NULL REFERENCES users(id),
  portal_url      TEXT,                    -- URL de Stripe Customer Portal (corta duración)
  session_id      TEXT UNIQUE,             -- ID de sesión Stripe: bps_...
  return_url      TEXT NOT NULL,           -- URL de retorno tras salir del portal
  status          TEXT NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending','active','expired','error')),
  error_message   TEXT,
  expires_at      TIMESTAMPTZ,             -- TTL del portal URL (~60min en Stripe)
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_portal_sessions_org ON billing_portal_sessions(org_id);
CREATE INDEX idx_portal_sessions_status ON billing_portal_sessions(status)
  WHERE status IN ('pending','active');

CREATE TRIGGER portal_sessions_updated_at
  BEFORE UPDATE ON billing_portal_sessions
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 2. Solicitar sesión de portal (persiste intent, worker genera URL)
CREATE OR REPLACE FUNCTION request_billing_portal(
  p_org_id       UUID,
  p_user_id      UUID,
  p_return_url   TEXT
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_sub       RECORD;
  v_session   UUID;
BEGIN
  -- Verificar que el org tiene suscripción activa con Stripe
  SELECT s.provider_sub_id, s.status
  INTO v_sub
  FROM subscriptions s
  WHERE s.org_id = p_org_id
    AND s.provider = 'stripe'
    AND s.status IN ('active','past_due','trialing')
  ORDER BY s.created_at DESC
  LIMIT 1;

  IF NOT FOUND OR v_sub.provider_sub_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', FALSE,
      'error',   'no_stripe_subscription',
      'message', 'El org no tiene una suscripción Stripe activa'
    );
  END IF;

  -- Verificar que el solicitante es owner o admin
  IF NOT EXISTS (
    SELECT 1 FROM organization_members
    WHERE org_id = p_org_id
      AND user_id = p_user_id
      AND role IN ('owner','admin')
  ) THEN
    RETURN jsonb_build_object(
      'success', FALSE,
      'error',   'forbidden',
      'message', 'Solo owner/admin pueden acceder al portal de billing'
    );
  END IF;

  -- Crear sesión en estado pending (worker la completará)
  INSERT INTO billing_portal_sessions (org_id, requested_by, return_url)
  VALUES (p_org_id, p_user_id, p_return_url)
  RETURNING id INTO v_session;

  RETURN jsonb_build_object(
    'success',           TRUE,
    'session_id',        v_session,
    'status',            'pending',
    'provider_sub_id',   v_sub.provider_sub_id,
    'message',           'Sesión de portal solicitada. Llama a Stripe API para generar URL.'
  );
END;
$$;

-- 3. Registrar URL generada por el worker Stripe
CREATE OR REPLACE FUNCTION fulfill_billing_portal(
  p_internal_session_id  UUID,
  p_stripe_session_id    TEXT,
  p_portal_url           TEXT,
  p_expires_at           TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE billing_portal_sessions
  SET portal_url  = p_portal_url,
      session_id  = p_stripe_session_id,
      status      = 'active',
      expires_at  = COALESCE(p_expires_at, NOW() + INTERVAL '60 minutes')
  WHERE id = p_internal_session_id
    AND status = 'pending';

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'session_not_found_or_not_pending');
  END IF;

  RETURN jsonb_build_object(
    'success',    TRUE,
    'portal_url', p_portal_url,
    'expires_at', COALESCE(p_expires_at, NOW() + INTERVAL '60 minutes')
  );
END;
$$;

-- 4. Obtener URL activa para redirigir al usuario
CREATE OR REPLACE FUNCTION get_billing_portal_url(
  p_org_id  UUID,
  p_user_id UUID
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_session RECORD;
BEGIN
  SELECT portal_url, status, expires_at, id
  INTO v_session
  FROM billing_portal_sessions
  WHERE org_id = p_org_id
    AND status = 'active'
    AND (expires_at IS NULL OR expires_at > NOW())
  ORDER BY created_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'no_active_portal_session');
  END IF;

  RETURN jsonb_build_object(
    'success',    TRUE,
    'portal_url', v_session.portal_url,
    'expires_at', v_session.expires_at
  );
END;
$$;

-- 5. Marcar sesiones expiradas (llamar periódicamente)
CREATE OR REPLACE FUNCTION expire_old_portal_sessions()
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_count INT;
BEGIN
  UPDATE billing_portal_sessions
  SET status = 'expired'
  WHERE status = 'active'
    AND expires_at IS NOT NULL
    AND expires_at < NOW();
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

COMMENT ON TABLE billing_portal_sessions IS
  'Sesiones del Stripe Customer Portal. Worker externo llama Stripe API y fulfill_billing_portal().';
COMMENT ON FUNCTION request_billing_portal(UUID, UUID, TEXT) IS
  'Crea sesión de portal en estado pending. Requiere owner/admin y suscripción Stripe.';
COMMENT ON FUNCTION fulfill_billing_portal(UUID, TEXT, TEXT, TIMESTAMPTZ) IS
  'Registra URL de portal generada por el worker Stripe. Activa la sesión.';
COMMENT ON FUNCTION get_billing_portal_url(UUID, UUID) IS
  'Devuelve URL activa del portal para redirigir al usuario.';
