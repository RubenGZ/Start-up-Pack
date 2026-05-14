-- onboarding.sql — onboarding multi-step para nuevos orgs [SUP-11]
-- Pasos: welcome → org_created → profile_complete → invite_sent → done

-- 1. Tabla de progreso de onboarding por usuario
CREATE TABLE onboarding_progress (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE UNIQUE,
  steps        JSONB NOT NULL DEFAULT '{
    "welcome":          false,
    "org_created":      false,
    "profile_complete": false,
    "invite_sent":      false
  }'::JSONB,
  completed_at TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER onboarding_updated_at
  BEFORE UPDATE ON onboarding_progress
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 2. Tabla de invitaciones pendientes
CREATE TABLE member_invites (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  org_id     UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  invited_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  email      CITEXT NOT NULL,
  role       TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('admin','member')),
  token_hash TEXT NOT NULL UNIQUE,
  accepted   BOOLEAN NOT NULL DEFAULT FALSE,
  expires_at TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '7 days',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (org_id, email)
);

CREATE INDEX idx_invites_org ON member_invites(org_id);
CREATE INDEX idx_invites_email ON member_invites(email);

-- 3. start_onboarding — inicializa progreso (idempotente)
CREATE OR REPLACE FUNCTION start_onboarding(p_user_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_row onboarding_progress%ROWTYPE;
BEGIN
  INSERT INTO onboarding_progress (user_id, steps)
  VALUES (p_user_id, '{
    "welcome": true,
    "org_created": false,
    "profile_complete": false,
    "invite_sent": false
  }'::JSONB)
  ON CONFLICT (user_id) DO UPDATE SET updated_at = NOW()
  RETURNING * INTO v_row;

  RETURN get_onboarding_status(p_user_id);
END;
$$;

-- 4. complete_onboarding_step — marca un paso como completado
CREATE OR REPLACE FUNCTION complete_onboarding_step(
  p_user_id UUID,
  p_step    TEXT   -- 'welcome' | 'org_created' | 'profile_complete' | 'invite_sent'
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_valid_steps TEXT[] := ARRAY['welcome','org_created','profile_complete','invite_sent'];
  v_steps       JSONB;
  v_all_done    BOOLEAN;
BEGIN
  IF NOT (p_step = ANY(v_valid_steps)) THEN
    RETURN jsonb_build_object('error', 'invalid_step', 'valid', v_valid_steps);
  END IF;

  UPDATE onboarding_progress
  SET steps = steps || jsonb_build_object(p_step, TRUE),
      updated_at = NOW()
  WHERE user_id = p_user_id
  RETURNING steps INTO v_steps;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'not_started');
  END IF;

  -- Completar si todos los pasos requeridos están done
  v_all_done := (v_steps->>'welcome')::BOOLEAN
    AND (v_steps->>'org_created')::BOOLEAN
    AND (v_steps->>'profile_complete')::BOOLEAN;

  IF v_all_done THEN
    UPDATE onboarding_progress
    SET completed_at = COALESCE(completed_at, NOW())
    WHERE user_id = p_user_id;
  END IF;

  RETURN get_onboarding_status(p_user_id);
END;
$$;

-- 5. get_onboarding_status — estado actual + % completado
CREATE OR REPLACE FUNCTION get_onboarding_status(p_user_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_row onboarding_progress%ROWTYPE;
DECLARE v_completed_steps INT;
BEGIN
  SELECT * INTO v_row FROM onboarding_progress WHERE user_id = p_user_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('started', FALSE);
  END IF;

  SELECT COUNT(*) INTO v_completed_steps
  FROM jsonb_each_text(v_row.steps)
  WHERE value = 'true';

  RETURN jsonb_build_object(
    'started',      TRUE,
    'steps',        v_row.steps,
    'progress_pct', ROUND((v_completed_steps::NUMERIC / 4) * 100),
    'completed',    v_row.completed_at IS NOT NULL,
    'completed_at', v_row.completed_at
  );
END;
$$;

-- 6. invite_member — envía invitación a un miembro del equipo
CREATE OR REPLACE FUNCTION invite_member(
  p_org_id     UUID,
  p_invited_by UUID,
  p_email      CITEXT,
  p_role       TEXT DEFAULT 'member'
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_token      TEXT;
  v_token_hash TEXT;
  v_invite_id  UUID;
BEGIN
  -- Verificar que quien invita es owner/admin
  IF NOT EXISTS (
    SELECT 1 FROM organization_members
    WHERE org_id = p_org_id AND user_id = p_invited_by
      AND role IN ('owner','admin')
  ) THEN
    RETURN jsonb_build_object('error', 'unauthorized');
  END IF;

  -- Si ya es miembro, no invitar
  IF EXISTS (
    SELECT 1 FROM users u JOIN organization_members om ON om.user_id = u.id
    WHERE u.email = p_email AND om.org_id = p_org_id
  ) THEN
    RETURN jsonb_build_object('error', 'already_member');
  END IF;

  v_token      := encode(gen_random_bytes(32), 'hex');
  v_token_hash := encode(digest(v_token, 'sha256'), 'hex');

  INSERT INTO member_invites (org_id, invited_by, email, role, token_hash)
  VALUES (p_org_id, p_invited_by, p_email, p_role, v_token_hash)
  ON CONFLICT (org_id, email) DO UPDATE
    SET token_hash = EXCLUDED.token_hash,
        expires_at = NOW() + INTERVAL '7 days',
        accepted   = FALSE
  RETURNING id INTO v_invite_id;

  -- Marcar paso invite_sent en onboarding
  PERFORM complete_onboarding_step(p_invited_by, 'invite_sent');

  RETURN jsonb_build_object(
    'invite_id', v_invite_id,
    'token',     v_token,   -- enviar por email; nunca almacenar en cliente
    'email',     p_email,
    'role',      p_role,
    'expires_at', NOW() + INTERVAL '7 days'
  );
END;
$$;

-- 7. accept_invite — acepta invitación y une al usuario a la org
CREATE OR REPLACE FUNCTION accept_invite(p_token TEXT, p_user_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_invite member_invites%ROWTYPE;
BEGIN
  SELECT * INTO v_invite
  FROM member_invites
  WHERE token_hash = encode(digest(p_token, 'sha256'), 'hex')
    AND accepted = FALSE
    AND expires_at > NOW();

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'invalid_or_expired_invite');
  END IF;

  INSERT INTO organization_members (org_id, user_id, role)
  VALUES (v_invite.org_id, p_user_id, v_invite.role)
  ON CONFLICT (org_id, user_id) DO NOTHING;

  UPDATE member_invites SET accepted = TRUE WHERE id = v_invite.id;

  RETURN jsonb_build_object(
    'org_id', v_invite.org_id,
    'role',   v_invite.role,
    'joined', TRUE
  );
END;
$$;
