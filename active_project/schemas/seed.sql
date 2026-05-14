-- seed.sql — datos demo para desarrollo local [SUP-7]
-- Demo org + admin user + free plan subscription
-- IDEMPOTENTE: ON CONFLICT DO NOTHING en todos los inserts

-- UUIDs fijos para dev (reproducibles, fácil referencia en tests)
DO $$
DECLARE
  v_org_id  UUID := '00000000-0000-0000-0000-000000000001';
  v_user_id UUID := '00000000-0000-0000-0000-000000000002';
  v_sub_id  UUID := '00000000-0000-0000-0000-000000000003';
BEGIN

  -- 1. Organización demo
  INSERT INTO organizations (id, slug, name, plan, is_active)
  VALUES (v_org_id, 'demo', 'Demo Corp', 'free', TRUE)
  ON CONFLICT (id) DO NOTHING;

  -- 2. Usuario admin
  INSERT INTO users (id, email, name, role, is_active)
  VALUES (v_user_id, 'admin@demo.com', 'Admin Demo', 'owner', TRUE)
  ON CONFLICT (id) DO NOTHING;

  -- 3. Vincular user como owner de la org
  INSERT INTO organization_members (org_id, user_id, role)
  VALUES (v_org_id, v_user_id, 'owner')
  ON CONFLICT (org_id, user_id) DO NOTHING;

  -- 4. Suscripción free activa para la org demo
  INSERT INTO subscriptions (
    id, org_id, plan, status, provider,
    current_period_start, current_period_end
  )
  VALUES (
    v_sub_id, v_org_id, 'free', 'active', NULL,
    NOW(), NOW() + INTERVAL '1 year'
  )
  ON CONFLICT (id) DO NOTHING;

  RAISE NOTICE '[seed] Demo data OK — org=%, user=%', v_org_id, v_user_id;

END $$;
