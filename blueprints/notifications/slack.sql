-- slack.sql — Slack notifications outbound [SUP-22]
-- Extiende notification_queue con canal 'slack'
-- Worker externo consume via dequeue_notifications('slack') y llama a Slack API
-- Config: slack_webhook_url almacenada en org_slack_config (tabla propia)

-- 1. Configuración de Slack por org
CREATE TABLE IF NOT EXISTS org_slack_config (
  org_id          UUID PRIMARY KEY REFERENCES organizations(id) ON DELETE CASCADE,
  webhook_url     TEXT NOT NULL,           -- Slack Incoming Webhook URL (gitignored en prod)
  default_channel TEXT DEFAULT '#general', -- canal destino (referencia, no usado por webhook)
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER org_slack_config_updated_at
  BEFORE UPDATE ON org_slack_config
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 2. Configurar/actualizar webhook de Slack para un org
CREATE OR REPLACE FUNCTION set_slack_webhook(
  p_org_id      UUID,
  p_webhook_url TEXT,
  p_channel     TEXT DEFAULT '#general',
  p_set_by      UUID DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- Solo owner/admin pueden configurar
  IF p_set_by IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM organization_members
    WHERE org_id = p_org_id AND user_id = p_set_by AND role IN ('owner','admin')
  ) THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'forbidden');
  END IF;

  INSERT INTO org_slack_config (org_id, webhook_url, default_channel)
  VALUES (p_org_id, p_webhook_url, p_channel)
  ON CONFLICT (org_id) DO UPDATE
    SET webhook_url     = EXCLUDED.webhook_url,
        default_channel = EXCLUDED.default_channel,
        is_active       = TRUE,
        updated_at      = NOW();

  RETURN jsonb_build_object('success', TRUE, 'channel', p_channel);
END;
$$;

-- 3. Encolar notificación Slack (entra en notification_queue)
CREATE OR REPLACE FUNCTION send_slack_notification(
  p_org_id   UUID,
  p_text     TEXT,
  p_blocks   JSONB DEFAULT NULL,
  p_user_id  UUID DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_config  RECORD;
  v_notif   UUID;
  v_queue   UUID;
  v_payload JSONB;
BEGIN
  -- Verificar config activa
  SELECT webhook_url, default_channel
  INTO v_config
  FROM org_slack_config
  WHERE org_id = p_org_id AND is_active = TRUE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', FALSE,
      'error',   'no_slack_config',
      'message', 'Configura webhook con set_slack_webhook() primero'
    );
  END IF;

  -- Construir payload para el worker
  v_payload := jsonb_build_object(
    'webhook_url', v_config.webhook_url,
    'text',        p_text,
    'blocks',      p_blocks
  );

  -- Registrar en notifications
  INSERT INTO notifications (
    user_id, org_id, type, channel, title, body, data, status
  )
  VALUES (
    p_user_id, p_org_id, 'slack_message', 'slack',
    'Slack notification', p_text,
    v_payload, 'pending'
  )
  RETURNING id INTO v_notif;

  -- Encolar para el worker
  INSERT INTO notification_queue (notification_id, channel, payload)
  VALUES (v_notif, 'slack', v_payload)
  RETURNING id INTO v_queue;

  RETURN jsonb_build_object(
    'success',         TRUE,
    'notification_id', v_notif,
    'queue_id',        v_queue,
    'channel',         v_config.default_channel
  );
END;
$$;

-- 4. Verificar si un org tiene Slack configurado
CREATE OR REPLACE FUNCTION has_slack_configured(p_org_id UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM org_slack_config
    WHERE org_id = p_org_id AND is_active = TRUE
  );
END;
$$;

-- 5. Desactivar Slack para un org
CREATE OR REPLACE FUNCTION disable_slack(p_org_id UUID, p_by UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM organization_members
    WHERE org_id = p_org_id AND user_id = p_by AND role IN ('owner','admin')
  ) THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'forbidden');
  END IF;

  UPDATE org_slack_config SET is_active = FALSE WHERE org_id = p_org_id;
  RETURN jsonb_build_object('success', TRUE);
END;
$$;

COMMENT ON TABLE org_slack_config IS
  'Config de Slack por org. webhook_url = Incoming Webhook de Slack (secreto — no committear).';
COMMENT ON FUNCTION send_slack_notification(UUID, TEXT, JSONB, UUID) IS
  'Encola mensaje Slack en notification_queue. Worker consume con dequeue_notifications(''slack'').';
COMMENT ON FUNCTION set_slack_webhook(UUID, TEXT, TEXT, UUID) IS
  'Configura Incoming Webhook de Slack para el org. Solo owner/admin.';
