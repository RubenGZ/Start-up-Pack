-- auth.flow.sql — lógica de flujo: magic link + sesiones

-- Solicita magic link: inserta registro y retorna token raw (para enviar por email)
CREATE OR REPLACE FUNCTION request_magic_link(p_email CITEXT)
RETURNS TEXT AS $$
DECLARE
  v_token      TEXT;
  v_token_hash TEXT;
BEGIN
  v_token      := encode(gen_random_bytes(32), 'hex');
  v_token_hash := encode(digest(v_token, 'sha256'), 'hex');

  DELETE FROM magic_links WHERE email = p_email;

  INSERT INTO magic_links (email, token_hash)
  VALUES (p_email, v_token_hash);

  RETURN v_token;
END;
$$ LANGUAGE plpgsql;

-- Verifica magic link: valida token, crea o recupera usuario, retorna session token raw
CREATE OR REPLACE FUNCTION verify_magic_link(
  p_token      TEXT,
  p_ip         INET    DEFAULT NULL,
  p_user_agent TEXT    DEFAULT NULL
)
RETURNS TABLE(session_token TEXT, user_id UUID, is_new_user BOOLEAN) AS $$
DECLARE
  v_token_hash TEXT;
  v_link       magic_links%ROWTYPE;
  v_user_id    UUID;
  v_new_user   BOOLEAN := FALSE;
  v_sess_token TEXT;
  v_sess_hash  TEXT;
BEGIN
  v_token_hash := encode(digest(p_token, 'sha256'), 'hex');

  SELECT * INTO v_link
  FROM magic_links
  WHERE token_hash = v_token_hash
    AND used = FALSE
    AND expires_at > NOW();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invalid_or_expired_token';
  END IF;

  -- Upsert usuario
  INSERT INTO users (email)
  VALUES (v_link.email)
  ON CONFLICT (email) DO UPDATE SET updated_at = NOW()
  RETURNING id INTO v_user_id;

  IF NOT FOUND THEN
    SELECT id INTO v_user_id FROM users WHERE email = v_link.email;
  ELSE
    v_new_user := TRUE;
  END IF;

  -- Marcar link como usado
  UPDATE magic_links SET used = TRUE WHERE id = v_link.id;

  -- Crear sesión
  v_sess_token := encode(gen_random_bytes(32), 'hex');
  v_sess_hash  := encode(digest(v_sess_token, 'sha256'), 'hex');

  INSERT INTO sessions (user_id, token_hash, ip_address, user_agent, expires_at)
  VALUES (v_user_id, v_sess_hash, p_ip, p_user_agent, NOW() + INTERVAL '30 days');

  RETURN QUERY SELECT v_sess_token, v_user_id, v_new_user;
END;
$$ LANGUAGE plpgsql;

-- Valida sesión activa: retorna user_id o NULL
CREATE OR REPLACE FUNCTION validate_session(p_token TEXT)
RETURNS UUID AS $$
DECLARE
  v_token_hash TEXT;
  v_user_id    UUID;
BEGIN
  v_token_hash := encode(digest(p_token, 'sha256'), 'hex');

  SELECT user_id INTO v_user_id
  FROM sessions
  WHERE token_hash = v_token_hash
    AND expires_at > NOW();

  RETURN v_user_id;
END;
$$ LANGUAGE plpgsql;

-- Revoca sesión
CREATE OR REPLACE FUNCTION revoke_session(p_token TEXT)
RETURNS void AS $$
BEGIN
  DELETE FROM sessions
  WHERE token_hash = encode(digest(p_token, 'sha256'), 'hex');
END;
$$ LANGUAGE plpgsql;
