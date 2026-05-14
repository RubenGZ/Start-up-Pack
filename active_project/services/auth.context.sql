-- auth.context.sql — contexto de sesión completo [SUP-10]
-- Funciones para multi-tenant auth: quien soy, signup, context PG, logout global

-- 1. get_session_context — "¿quién soy?"
-- Retorna JSONB con user + org activa + role (para el endpoint GET /me)
CREATE OR REPLACE FUNCTION get_session_context(p_token TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_token_hash TEXT;
  v_user_id    UUID;
  v_result     JSONB;
BEGIN
  v_token_hash := encode(digest(p_token, 'sha256'), 'hex');

  SELECT s.user_id INTO v_user_id
  FROM sessions s
  WHERE s.token_hash = v_token_hash
    AND s.expires_at > NOW();

  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'invalid_session');
  END IF;

  SELECT jsonb_build_object(
    'user', jsonb_build_object(
      'id',         u.id,
      'email',      u.email,
      'name',       u.name,
      'role',       u.role,
      'created_at', u.created_at
    ),
    'orgs', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id',    o.id,
        'slug',  o.slug,
        'name',  o.name,
        'plan',  o.plan,
        'role',  om.role
      ) ORDER BY om.joined_at)
      FROM organization_members om
      JOIN organizations o ON o.id = om.org_id AND o.is_active = TRUE
      WHERE om.user_id = v_user_id
    ), '[]'::JSONB),
    'session_expires_at', (
      SELECT expires_at FROM sessions
      WHERE token_hash = v_token_hash
    )
  ) INTO v_result
  FROM users u
  WHERE u.id = v_user_id;

  RETURN v_result;
END;
$$;

-- 2. complete_signup — crea org + owner + free subscription en primer login
-- Idempotente: si ya tiene org, retorna la existente
CREATE OR REPLACE FUNCTION complete_signup(
  p_user_id  UUID,
  p_org_name TEXT,
  p_org_slug TEXT
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_org_id  UUID;
  v_sub_id  UUID;
  v_exists  BOOLEAN;
BEGIN
  -- Verificar si ya tiene una org como owner
  SELECT om.org_id INTO v_org_id
  FROM organization_members om
  WHERE om.user_id = p_user_id AND om.role = 'owner'
  LIMIT 1;

  IF v_org_id IS NOT NULL THEN
    RETURN jsonb_build_object('org_id', v_org_id, 'created', FALSE);
  END IF;

  -- Validar slug único
  SELECT EXISTS(SELECT 1 FROM organizations WHERE slug = p_org_slug) INTO v_exists;
  IF v_exists THEN
    RETURN jsonb_build_object('error', 'slug_taken');
  END IF;

  -- Crear org
  INSERT INTO organizations (name, slug, plan)
  VALUES (p_org_name, p_org_slug, 'free')
  RETURNING id INTO v_org_id;

  -- Añadir user como owner
  INSERT INTO organization_members (org_id, user_id, role)
  VALUES (v_org_id, p_user_id, 'owner');

  -- Crear suscripción free
  INSERT INTO subscriptions (org_id, plan, status, current_period_start, current_period_end)
  VALUES (v_org_id, 'free', 'active', NOW(), NOW() + INTERVAL '1 year')
  RETURNING id INTO v_sub_id;

  RETURN jsonb_build_object(
    'org_id',  v_org_id,
    'sub_id',  v_sub_id,
    'created', TRUE
  );
END;
$$;

-- 3. set_session_context — establece variables PG de sesión para audit trail
-- Invocar al inicio de cada transacción de la app:
--   SELECT set_session_context('token', '1.2.3.4', 'sessionid');
CREATE OR REPLACE FUNCTION set_session_context(
  p_token      TEXT,
  p_ip         TEXT DEFAULT NULL,
  p_session_id TEXT DEFAULT NULL
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_user_id UUID;
  v_org_id  UUID;
BEGIN
  v_user_id := validate_session(p_token);

  IF v_user_id IS NOT NULL THEN
    PERFORM set_config('app.current_user_id', v_user_id::TEXT, TRUE);

    SELECT om.org_id INTO v_org_id
    FROM organization_members om
    WHERE om.user_id = v_user_id AND om.role = 'owner'
    LIMIT 1;

    IF v_org_id IS NOT NULL THEN
      PERFORM set_config('app.current_org_id', v_org_id::TEXT, TRUE);
    END IF;
  END IF;

  IF p_ip IS NOT NULL THEN
    PERFORM set_config('app.current_ip', p_ip, TRUE);
  END IF;
  IF p_session_id IS NOT NULL THEN
    PERFORM set_config('app.current_session_id', p_session_id, TRUE);
  END IF;
END;
$$;

-- 4. revoke_all_sessions — logout de todos los dispositivos
CREATE OR REPLACE FUNCTION revoke_all_sessions(p_user_id UUID)
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_deleted INT;
BEGIN
  DELETE FROM sessions WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;
