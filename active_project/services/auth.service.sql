-- auth.service.sql — gestión de sesiones y tokens

CREATE TABLE sessions (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash  TEXT NOT NULL UNIQUE,
  ip_address  INET,
  user_agent  TEXT,
  expires_at  TIMESTAMPTZ NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_sessions_user ON sessions(user_id);
CREATE INDEX idx_sessions_expires ON sessions(expires_at);

CREATE TABLE magic_links (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email      CITEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  used       BOOLEAN NOT NULL DEFAULT FALSE,
  expires_at TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '15 minutes',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Limpieza automática de links y sesiones expiradas
CREATE OR REPLACE FUNCTION cleanup_expired_auth()
RETURNS void AS $$
BEGIN
  DELETE FROM magic_links WHERE expires_at < NOW();
  DELETE FROM sessions WHERE expires_at < NOW();
END;
$$ LANGUAGE plpgsql;
