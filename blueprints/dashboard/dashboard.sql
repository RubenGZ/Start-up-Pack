-- dashboard.sql — métricas por org para dashboard principal [SUP-20]
-- Funciones JSONB puras: sin tablas nuevas, agrega datos existentes
-- Consume: users, organization_members, subscriptions, audit_log, api_keys, notifications

-- 1. Snapshot de billing actual
CREATE OR REPLACE FUNCTION billing_snapshot(p_org_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result JSONB;
BEGIN
  SELECT jsonb_build_object(
    'plan',                 s.plan,
    'status',               s.status,
    'provider',             s.provider,
    'provider_sub_id',      s.provider_sub_id,
    'current_period_start', s.current_period_start,
    'current_period_end',   s.current_period_end,
    'canceled_at',          s.canceled_at,
    'org_plan',             o.plan
  )
  INTO v_result
  FROM organizations o
  LEFT JOIN subscriptions s ON s.org_id = o.id AND s.status != 'canceled'
  WHERE o.id = p_org_id
  ORDER BY s.created_at DESC
  LIMIT 1;

  RETURN COALESCE(v_result, jsonb_build_object('plan', 'free', 'status', 'active'));
END;
$$;

-- 2. Resumen de miembros del org
CREATE OR REPLACE FUNCTION members_summary(p_org_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result JSONB;
BEGIN
  SELECT jsonb_build_object(
    'total',   COUNT(*),
    'owners',  COUNT(*) FILTER (WHERE om.role = 'owner'),
    'admins',  COUNT(*) FILTER (WHERE om.role = 'admin'),
    'members', COUNT(*) FILTER (WHERE om.role = 'member'),
    'active',  COUNT(*) FILTER (WHERE u.is_active = TRUE)
  )
  INTO v_result
  FROM organization_members om
  JOIN users u ON u.id = om.user_id
  WHERE om.org_id = p_org_id;

  RETURN COALESCE(v_result, '{"total":0}'::JSONB);
END;
$$;

-- 3. Actividad reciente del org (últimos N eventos audit_log)
CREATE OR REPLACE FUNCTION recent_activity(
  p_org_id  UUID,
  p_limit   INT DEFAULT 20
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result JSONB;
BEGIN
  SELECT jsonb_agg(
    jsonb_build_object(
      'id',         al.id,
      'table',      al.table_name,
      'record_id',  al.record_id,
      'action',     al.action,
      'changed_by', al.changed_by,
      'created_at', al.created_at
    ) ORDER BY al.created_at DESC
  )
  INTO v_result
  FROM audit_log al
  WHERE al.org_id = p_org_id
  LIMIT p_limit;

  RETURN COALESCE(v_result, '[]'::JSONB);
END;
$$;

-- 4. Resumen de API keys activas
CREATE OR REPLACE FUNCTION api_keys_summary(p_org_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result JSONB;
BEGIN
  SELECT jsonb_build_object(
    'total',    COUNT(*),
    'active',   COUNT(*) FILTER (WHERE revoked_at IS NULL AND (expires_at IS NULL OR expires_at > NOW())),
    'revoked',  COUNT(*) FILTER (WHERE revoked_at IS NOT NULL),
    'expired',  COUNT(*) FILTER (WHERE expires_at IS NOT NULL AND expires_at <= NOW() AND revoked_at IS NULL)
  )
  INTO v_result
  FROM api_keys
  WHERE org_id = p_org_id;

  RETURN COALESCE(v_result, '{"total":0,"active":0}'::JSONB);
END;
$$;

-- 5. Notificaciones no leídas del usuario en el contexto del org
CREATE OR REPLACE FUNCTION unread_notifications_summary(
  p_user_id UUID,
  p_org_id  UUID
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_count INT;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM notifications
  WHERE user_id = p_user_id
    AND org_id  = p_org_id
    AND read_at IS NULL
    AND status != 'failed';

  RETURN jsonb_build_object('unread_count', v_count);
END;
$$;

-- 6. Dashboard completo — punto de entrada único
CREATE OR REPLACE FUNCTION org_dashboard(
  p_org_id  UUID,
  p_user_id UUID DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_org JSONB;
BEGIN
  SELECT jsonb_build_object(
    'org_id',        o.id,
    'org_name',      o.name,
    'org_slug',      o.slug,
    'is_active',     o.is_active,
    'created_at',    o.created_at
  )
  INTO v_org
  FROM organizations o
  WHERE o.id = p_org_id;

  IF v_org IS NULL THEN
    RETURN jsonb_build_object('error', 'org_not_found');
  END IF;

  RETURN v_org
    || jsonb_build_object('billing',  billing_snapshot(p_org_id))
    || jsonb_build_object('members',  members_summary(p_org_id))
    || jsonb_build_object('api_keys', api_keys_summary(p_org_id))
    || jsonb_build_object('activity', recent_activity(p_org_id, 10))
    || CASE
         WHEN p_user_id IS NOT NULL
         THEN jsonb_build_object('notifications', unread_notifications_summary(p_user_id, p_org_id))
         ELSE '{}'::JSONB
       END;
END;
$$;

COMMENT ON FUNCTION org_dashboard(UUID, UUID) IS
  'Dashboard completo por org. Agrega billing, miembros, api_keys, actividad y notificaciones en un JSONB.';
COMMENT ON FUNCTION billing_snapshot(UUID) IS
  'Snapshot del plan y suscripción activa del org.';
COMMENT ON FUNCTION members_summary(UUID) IS
  'Conteo de miembros por rol en el org.';
COMMENT ON FUNCTION recent_activity(UUID, INT) IS
  'Últimos N eventos de audit_log del org.';
COMMENT ON FUNCTION api_keys_summary(UUID) IS
  'Conteo de API keys por estado en el org.';
COMMENT ON FUNCTION unread_notifications_summary(UUID, UUID) IS
  'Notificaciones no leídas del usuario en el org.';
