-- api_keys.sql — API keys por org con prefix+hash pattern [SUP-17]
-- Formato: hk_live_<32 hex chars> (prefix visible, secret nunca almacenado)
-- Solo se almacena: prefix (8 chars) + SHA-256 del secret completo

-- 1. Tabla de API keys
CREATE TABLE api_keys (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  org_id       UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  created_by   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  prefix       TEXT NOT NULL,                   -- "hk_live_XXXXXXXX" — visible en UI
  key_hash     TEXT NOT NULL UNIQUE,            -- SHA-256 del key completo
  scopes       TEXT[] NOT NULL DEFAULT '{}',    -- ['read', 'write', 'admin']
  last_used_at TIMESTAMPTZ,
  expires_at   TIMESTAMPTZ,                     -- NULL = no expira
  revoked_at   TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_api_keys_org     ON api_keys(org_id);
CREATE INDEX idx_api_keys_prefix  ON api_keys(prefix);
CREATE INDEX idx_api_keys_active  ON api_keys(org_id)
  WHERE revoked_at IS NULL;

-- 2. Log de uso (rate limiting + auditoría de keys)
CREATE TABLE api_key_usage (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  key_id     UUID NOT NULL REFERENCES api_keys(id) ON DELETE CASCADE,
  org_id     UUID NOT NULL,
  endpoint   TEXT,
  ip_address INET,
  status     SMALLINT,   -- HTTP status code
  used_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_key_usage_key  ON api_key_usage(key_id, used_at DESC);
CREATE INDEX idx_key_usage_org  ON api_key_usage(org_id, used_at DESC);

-- 3. create_api_key — genera key y devuelve el secret UNA SOLA VEZ
CREATE OR REPLACE FUNCTION create_api_key(
  p_org_id     UUID,
  p_created_by UUID,
  p_name       TEXT,
  p_scopes     TEXT[]    DEFAULT ARRAY['read'],
  p_expires_in INTERVAL  DEFAULT NULL,          -- ej: INTERVAL '90 days'
  p_env        TEXT      DEFAULT 'live'         -- 'live' | 'test'
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_secret     TEXT;
  v_prefix     TEXT;
  v_key_hash   TEXT;
  v_key_id     UUID;
  v_expires_at TIMESTAMPTZ;
BEGIN
  -- Solo owner/admin pueden crear keys
  IF NOT EXISTS (
    SELECT 1 FROM organization_members
    WHERE org_id = p_org_id AND user_id = p_created_by
      AND role IN ('owner','admin')
  ) THEN
    RETURN jsonb_build_object('error', 'unauthorized');
  END IF;

  -- Validar env
  IF p_env NOT IN ('live','test') THEN
    RETURN jsonb_build_object('error', 'invalid_env', 'valid', ARRAY['live','test']);
  END IF;

  -- Generar secret: hk_<env>_<32 hex bytes>
  v_secret   := 'hk_' || p_env || '_' || encode(gen_random_bytes(32), 'hex');
  v_prefix   := substring(v_secret FROM 1 FOR 16);   -- "hk_live_XXXXXXXX"
  v_key_hash := encode(digest(v_secret, 'sha256'), 'hex');

  -- Calcular expiración
  IF p_expires_in IS NOT NULL THEN
    v_expires_at := NOW() + p_expires_in;
  END IF;

  INSERT INTO api_keys (org_id, created_by, name, prefix, key_hash, scopes, expires_at)
  VALUES (p_org_id, p_created_by, p_name, v_prefix, v_key_hash, p_scopes, v_expires_at)
  RETURNING id INTO v_key_id;

  -- El secret se devuelve UNA SOLA VEZ — no se puede recuperar después
  RETURN jsonb_build_object(
    'key_id',     v_key_id,
    'secret',     v_secret,    -- ⚠ guardar ahora, no se muestra de nuevo
    'prefix',     v_prefix,
    'name',       p_name,
    'scopes',     p_scopes,
    'expires_at', v_expires_at,
    'warning',    'Store this secret immediately — it cannot be retrieved again'
  );
END;
$$;

-- 4. validate_api_key — autenticación desde middleware
CREATE OR REPLACE FUNCTION validate_api_key(
  p_secret   TEXT,
  p_endpoint TEXT DEFAULT NULL,
  p_ip       INET DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_key    api_keys%ROWTYPE;
  v_hash   TEXT;
BEGIN
  v_hash := encode(digest(p_secret, 'sha256'), 'hex');

  SELECT * INTO v_key FROM api_keys
  WHERE key_hash = v_hash
    AND revoked_at IS NULL
    AND (expires_at IS NULL OR expires_at > NOW());

  IF NOT FOUND THEN
    RETURN jsonb_build_object('valid', FALSE, 'error', 'invalid_or_expired_key');
  END IF;

  -- Actualizar last_used_at (sin bloqueo)
  UPDATE api_keys SET last_used_at = NOW() WHERE id = v_key.id;

  -- Registrar uso
  INSERT INTO api_key_usage (key_id, org_id, endpoint, ip_address, status)
  VALUES (v_key.id, v_key.org_id, p_endpoint, p_ip, 200);

  RETURN jsonb_build_object(
    'valid',      TRUE,
    'key_id',     v_key.id,
    'org_id',     v_key.org_id,
    'scopes',     v_key.scopes,
    'prefix',     v_key.prefix,
    'expires_at', v_key.expires_at
  );
END;
$$;

-- 5. revoke_api_key — revocación inmediata
CREATE OR REPLACE FUNCTION revoke_api_key(
  p_key_id    UUID,
  p_revoked_by UUID
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_org_id UUID;
BEGIN
  SELECT org_id INTO v_org_id FROM api_keys WHERE id = p_key_id;

  IF v_org_id IS NULL THEN
    RETURN jsonb_build_object('error', 'key_not_found');
  END IF;

  -- Solo owner/admin de la org pueden revocar
  IF NOT EXISTS (
    SELECT 1 FROM organization_members
    WHERE org_id = v_org_id AND user_id = p_revoked_by
      AND role IN ('owner','admin')
  ) THEN
    RETURN jsonb_build_object('error', 'unauthorized');
  END IF;

  UPDATE api_keys SET revoked_at = NOW()
  WHERE id = p_key_id AND revoked_at IS NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'already_revoked');
  END IF;

  RETURN jsonb_build_object('status', 'revoked', 'key_id', p_key_id);
END;
$$;

-- 6. list_org_api_keys — listado de keys de una org (nunca muestra el secret)
CREATE OR REPLACE FUNCTION list_org_api_keys(
  p_org_id    UUID,
  p_caller_id UUID,
  p_include_revoked BOOLEAN DEFAULT FALSE
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_keys JSONB;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM organization_members
    WHERE org_id = p_org_id AND user_id = p_caller_id
      AND role IN ('owner','admin')
  ) THEN
    RETURN jsonb_build_object('error', 'unauthorized');
  END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'key_id',       id,
    'name',         name,
    'prefix',       prefix,
    'scopes',       scopes,
    'active',       revoked_at IS NULL AND (expires_at IS NULL OR expires_at > NOW()),
    'last_used_at', last_used_at,
    'expires_at',   expires_at,
    'revoked_at',   revoked_at,
    'created_at',   created_at
  ) ORDER BY created_at DESC)
  INTO v_keys
  FROM api_keys
  WHERE org_id = p_org_id
    AND (p_include_revoked OR revoked_at IS NULL);

  RETURN jsonb_build_object(
    'org_id', p_org_id,
    'keys',   COALESCE(v_keys, '[]'::JSONB)
  );
END;
$$;

-- 7. check_key_scope — helper para middleware de autorización
CREATE OR REPLACE FUNCTION check_key_scope(p_key_id UUID, p_required_scope TEXT)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM api_keys
    WHERE id = p_key_id
      AND (p_required_scope = ANY(scopes) OR 'admin' = ANY(scopes))
      AND revoked_at IS NULL
  );
END;
$$;
