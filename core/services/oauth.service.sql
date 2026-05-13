-- oauth.service.sql — cuentas OAuth (Google, GitHub, etc.)

CREATE TABLE oauth_accounts (
  id                 UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id            UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider           TEXT NOT NULL CHECK (provider IN ('google','github','microsoft')),
  provider_user_id   TEXT NOT NULL,
  email              CITEXT,
  name               TEXT,
  avatar_url         TEXT,
  access_token_hash  TEXT,
  refresh_token_hash TEXT,
  token_expires_at   TIMESTAMPTZ,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (provider, provider_user_id)
);

CREATE INDEX idx_oauth_user ON oauth_accounts(user_id);
CREATE INDEX idx_oauth_provider ON oauth_accounts(provider, provider_user_id);

CREATE TRIGGER oauth_accounts_updated_at
  BEFORE UPDATE ON oauth_accounts
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Upsert OAuth: crea/actualiza cuenta y usuario asociado, retorna session token raw
CREATE OR REPLACE FUNCTION upsert_oauth_user(
  p_provider         TEXT,
  p_provider_user_id TEXT,
  p_email            CITEXT,
  p_name             TEXT    DEFAULT NULL,
  p_avatar_url       TEXT    DEFAULT NULL,
  p_ip               INET    DEFAULT NULL,
  p_user_agent       TEXT    DEFAULT NULL
)
RETURNS TABLE(session_token TEXT, user_id UUID, is_new_user BOOLEAN) AS $$
DECLARE
  v_user_id    UUID;
  v_new_user   BOOLEAN := FALSE;
  v_sess_token TEXT;
  v_sess_hash  TEXT;
BEGIN
  -- Upsert usuario por email
  INSERT INTO users (email, name, avatar_url)
  VALUES (p_email, p_name, p_avatar_url)
  ON CONFLICT (email) DO UPDATE
    SET name       = COALESCE(EXCLUDED.name, users.name),
        avatar_url = COALESCE(EXCLUDED.avatar_url, users.avatar_url),
        updated_at = NOW()
  RETURNING id INTO v_user_id;

  IF NOT FOUND THEN
    SELECT id INTO v_user_id FROM users WHERE email = p_email;
  ELSE
    v_new_user := TRUE;
  END IF;

  -- Upsert cuenta OAuth
  INSERT INTO oauth_accounts (user_id, provider, provider_user_id, email, name, avatar_url)
  VALUES (v_user_id, p_provider, p_provider_user_id, p_email, p_name, p_avatar_url)
  ON CONFLICT (provider, provider_user_id) DO UPDATE
    SET email      = EXCLUDED.email,
        name       = EXCLUDED.name,
        avatar_url = EXCLUDED.avatar_url,
        updated_at = NOW();

  -- Crear sesión
  v_sess_token := encode(gen_random_bytes(32), 'hex');
  v_sess_hash  := encode(digest(v_sess_token, 'sha256'), 'hex');

  INSERT INTO sessions (user_id, token_hash, ip_address, user_agent, expires_at)
  VALUES (v_user_id, v_sess_hash, p_ip, p_user_agent, NOW() + INTERVAL '30 days');

  RETURN QUERY SELECT v_sess_token, v_user_id, v_new_user;
END;
$$ LANGUAGE plpgsql;
