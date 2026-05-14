-- notifications.sql — sistema de notificaciones in-app + email queue [SUP-16]
-- Canales: in_app | email | both
-- Tipos: invite | billing | member_joined | payment_failed | custom

-- 1. Tabla principal de notificaciones
CREATE TABLE notifications (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  org_id       UUID REFERENCES organizations(id) ON DELETE CASCADE,
  type         TEXT NOT NULL,
  channel      TEXT NOT NULL DEFAULT 'in_app'
                 CHECK (channel IN ('in_app','email','both')),
  title        TEXT NOT NULL,
  body         TEXT NOT NULL,
  data         JSONB NOT NULL DEFAULT '{}',
  status       TEXT NOT NULL DEFAULT 'pending'
                 CHECK (status IN ('pending','sent','failed')),
  read_at      TIMESTAMPTZ,
  sent_at      TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_notifications_user    ON notifications(user_id, created_at DESC);
CREATE INDEX idx_notifications_org     ON notifications(org_id);
CREATE INDEX idx_notifications_unread  ON notifications(user_id) WHERE read_at IS NULL;
CREATE INDEX idx_notifications_status  ON notifications(status) WHERE status = 'pending';

-- 2. Cola de envío outbound (email / slack / webhook)
CREATE TABLE notification_queue (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  notification_id UUID NOT NULL REFERENCES notifications(id) ON DELETE CASCADE,
  channel         TEXT NOT NULL CHECK (channel IN ('email','slack','webhook')),
  payload         JSONB NOT NULL DEFAULT '{}',
  attempts        INT NOT NULL DEFAULT 0,
  max_attempts    INT NOT NULL DEFAULT 3,
  last_attempted  TIMESTAMPTZ,
  status          TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','sent','failed')),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_nqueue_pending ON notification_queue(status, created_at)
  WHERE status = 'pending';

-- 3. send_notification — crea notificación y encola si necesario
CREATE OR REPLACE FUNCTION send_notification(
  p_user_id UUID,
  p_org_id  UUID,
  p_type    TEXT,
  p_channel TEXT,
  p_title   TEXT,
  p_body    TEXT,
  p_data    JSONB DEFAULT '{}'
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_notif_id UUID;
BEGIN
  -- Validar usuario existe
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_user_id) THEN
    RETURN jsonb_build_object('error', 'user_not_found');
  END IF;

  -- Insertar notificación
  INSERT INTO notifications (user_id, org_id, type, channel, title, body, data)
  VALUES (p_user_id, p_org_id, p_type, p_channel, p_title, p_body, p_data)
  RETURNING id INTO v_notif_id;

  -- Encolar para envío externo si canal incluye email
  IF p_channel IN ('email', 'both') THEN
    INSERT INTO notification_queue (notification_id, channel, payload)
    VALUES (
      v_notif_id,
      'email',
      jsonb_build_object(
        'to',      (SELECT email FROM users WHERE id = p_user_id),
        'subject', p_title,
        'body',    p_body,
        'data',    p_data,
        'type',    p_type
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'notification_id', v_notif_id,
    'queued',          p_channel IN ('email','both'),
    'channel',         p_channel
  );
END;
$$;

-- 4. mark_as_read — marca una notificación como leída
CREATE OR REPLACE FUNCTION mark_as_read(
  p_notification_id UUID,
  p_user_id         UUID
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE notifications
  SET read_at = COALESCE(read_at, NOW())
  WHERE id = p_notification_id AND user_id = p_user_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'not_found_or_unauthorized');
  END IF;

  RETURN jsonb_build_object('status', 'read', 'notification_id', p_notification_id);
END;
$$;

-- 5. mark_all_read — marca todas las notificaciones de un usuario/org como leídas
CREATE OR REPLACE FUNCTION mark_all_read(p_user_id UUID, p_org_id UUID DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_count INT;
BEGIN
  UPDATE notifications
  SET read_at = NOW()
  WHERE user_id = p_user_id
    AND read_at IS NULL
    AND (p_org_id IS NULL OR org_id = p_org_id);

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN jsonb_build_object('status', 'ok', 'marked_count', v_count);
END;
$$;

-- 6. get_unread_count — conteo de no leídas por usuario
CREATE OR REPLACE FUNCTION get_unread_count(
  p_user_id UUID,
  p_org_id  UUID DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_count INT;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM notifications
  WHERE user_id = p_user_id
    AND read_at IS NULL
    AND (p_org_id IS NULL OR org_id = p_org_id);

  RETURN jsonb_build_object('unread', v_count, 'user_id', p_user_id);
END;
$$;

-- 7. list_notifications — listado paginado
CREATE OR REPLACE FUNCTION list_notifications(
  p_user_id    UUID,
  p_org_id     UUID DEFAULT NULL,
  p_limit      INT DEFAULT 20,
  p_offset     INT DEFAULT 0,
  p_unread_only BOOLEAN DEFAULT FALSE
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_rows JSONB;
BEGIN
  SELECT jsonb_agg(
    jsonb_build_object(
      'id',         id,
      'type',       type,
      'channel',    channel,
      'title',      title,
      'body',       body,
      'data',       data,
      'read',       read_at IS NOT NULL,
      'read_at',    read_at,
      'created_at', created_at
    ) ORDER BY created_at DESC
  )
  INTO v_rows
  FROM notifications
  WHERE user_id = p_user_id
    AND (p_org_id IS NULL OR org_id = p_org_id)
    AND (NOT p_unread_only OR read_at IS NULL)
  LIMIT p_limit OFFSET p_offset;

  RETURN jsonb_build_object(
    'notifications', COALESCE(v_rows, '[]'::JSONB),
    'limit',         p_limit,
    'offset',        p_offset
  );
END;
$$;

-- 8. dequeue_notifications — worker de envío (email/slack/webhook)
CREATE OR REPLACE FUNCTION dequeue_notifications(
  p_channel TEXT DEFAULT 'email',
  p_limit   INT DEFAULT 10
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_batch JSONB;
BEGIN
  WITH picked AS (
    SELECT id, notification_id, channel, payload, attempts
    FROM notification_queue
    WHERE status = 'pending'
      AND channel = p_channel
      AND attempts < max_attempts
    ORDER BY created_at
    LIMIT p_limit
    FOR UPDATE SKIP LOCKED
  ),
  updated AS (
    UPDATE notification_queue q
    SET attempts       = q.attempts + 1,
        last_attempted = NOW()
    FROM picked
    WHERE q.id = picked.id
    RETURNING q.id, q.notification_id, q.channel, q.payload, q.attempts
  )
  SELECT jsonb_agg(jsonb_build_object(
    'queue_id',        id,
    'notification_id', notification_id,
    'channel',         channel,
    'payload',         payload,
    'attempt',         attempts
  )) INTO v_batch FROM updated;

  RETURN jsonb_build_object(
    'batch',   COALESCE(v_batch, '[]'::JSONB),
    'channel', p_channel
  );
END;
$$;

-- 9. ack_notification_sent — confirma envío exitoso
CREATE OR REPLACE FUNCTION ack_notification_sent(
  p_queue_id       UUID,
  p_notification_id UUID
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE notification_queue SET status = 'sent' WHERE id = p_queue_id;
  UPDATE notifications SET status = 'sent', sent_at = NOW() WHERE id = p_notification_id;
END;
$$;

-- 10. ack_notification_failed — marca envío fallido definitivo
CREATE OR REPLACE FUNCTION ack_notification_failed(p_queue_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE notification_queue
  SET status = 'failed'
  WHERE id = p_queue_id AND attempts >= max_attempts;
END;
$$;
