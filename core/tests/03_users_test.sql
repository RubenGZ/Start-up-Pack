-- 03_users_test.sql — pgTAP: users / member management
-- Suite: list_org_members · remove_member · change_member_role · transfer_ownership
-- Verifica RBAC, invariantes de ownership y operaciones atómicas

BEGIN;

SELECT plan(16);

-- ── Fixtures ────────────────────────────────────────────────────────────────
INSERT INTO organizations (id, name, slug, plan)
VALUES ('00000000-0000-0000-0000-000000000001', 'Users Test Org', 'users-test', 'pro')
ON CONFLICT (id) DO NOTHING;

INSERT INTO users (id, email, name) VALUES
  ('00000000-0000-0000-0000-000000000010', 'owner@test.com',   'Owner User'),
  ('00000000-0000-0000-0000-000000000011', 'admin@test.com',   'Admin User'),
  ('00000000-0000-0000-0000-000000000012', 'member@test.com',  'Member User'),
  ('00000000-0000-0000-0000-000000000013', 'outside@test.com', 'Outside User')
ON CONFLICT (id) DO NOTHING;

INSERT INTO organization_members (org_id, user_id, role) VALUES
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000010', 'owner'),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000011', 'admin'),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000012', 'member')
ON CONFLICT DO NOTHING;

-- ── BLOQUE 1: list_org_members ───────────────────────────────────────────────

-- T1: miembro puede ver listado
SELECT ok(
  (list_org_members(
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000012'   -- member
  ))->>'error' IS NULL,
  'T1: member puede listar miembros del org'
);

-- T2: count correcto (3 miembros)
SELECT ok(
  (list_org_members(
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000010'
  ))->>'count' = '3',
  'T2: list_org_members devuelve count=3'
);

-- T3: usuario externo no puede listar
SELECT ok(
  (list_org_members(
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000013'   -- outside
  ))->>'error' = 'unauthorized',
  'T3: usuario externo recibe error=unauthorized en list_org_members'
);

-- ── BLOQUE 2: remove_member ───────────────────────────────────────────────────

-- T4: owner puede remover member
SELECT ok(
  (remove_member(
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000012',  -- target: member
    '00000000-0000-0000-0000-000000000010'   -- by: owner
  ))->>'status' = 'removed',
  'T4: owner puede remover member → status=removed'
);

SELECT ok(
  (SELECT count(*) = 0 FROM organization_members
   WHERE org_id = '00000000-0000-0000-0000-000000000001'
     AND user_id = '00000000-0000-0000-0000-000000000012'),
  'T5: member eliminado de organization_members'
);

-- T6: no se puede remover al owner
SELECT ok(
  (remove_member(
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000010',  -- target: owner
    '00000000-0000-0000-0000-000000000011'   -- by: admin
  ))->>'error' = 'cannot_remove_owner',
  'T6: no se puede remover al owner → error=cannot_remove_owner'
);

-- T7: admin no puede remover a otro admin
SELECT ok(
  (remove_member(
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000011',  -- target: admin
    '00000000-0000-0000-0000-000000000011'   -- by: mismo admin (fuerza el caso)
  ))->>'error' = 'admin_cannot_remove_admin',
  'T7: admin no puede remover a otro admin → error=admin_cannot_remove_admin'
);

-- Re-add member for remaining tests
INSERT INTO organization_members (org_id, user_id, role)
VALUES ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000012', 'member')
ON CONFLICT DO NOTHING;

-- ── BLOQUE 3: change_member_role ─────────────────────────────────────────────

-- T8: owner puede cambiar rol de member a admin
SELECT ok(
  (change_member_role(
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000012',  -- target: member
    'admin',
    '00000000-0000-0000-0000-000000000010'   -- by: owner
  ))->>'status' = 'role_changed',
  'T8: owner puede cambiar member → admin'
);

SELECT ok(
  (SELECT role = 'admin' FROM organization_members
   WHERE org_id = '00000000-0000-0000-0000-000000000001'
     AND user_id = '00000000-0000-0000-0000-000000000012'),
  'T9: rol actualizado a admin en DB'
);

-- T10: admin NO puede cambiar roles
SELECT ok(
  (change_member_role(
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000012',
    'member',
    '00000000-0000-0000-0000-000000000011'   -- by: admin
  ))->>'error' = 'unauthorized',
  'T10: admin no puede cambiar roles → error=unauthorized'
);

-- T11: rol inválido rechazado
SELECT ok(
  (change_member_role(
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000012',
    'superadmin',                             -- rol inválido
    '00000000-0000-0000-0000-000000000010'
  ))->>'error' = 'invalid_role',
  'T11: rol superadmin inválido → error=invalid_role'
);

-- T12: no se puede cambiar rol del owner directamente
SELECT ok(
  (change_member_role(
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000010',  -- target: owner
    'admin',
    '00000000-0000-0000-0000-000000000010'   -- by: mismo owner
  ))->>'error' = 'use_transfer_ownership_instead',
  'T12: cambiar rol del owner → error=use_transfer_ownership_instead'
);

-- ── BLOQUE 4: transfer_ownership ─────────────────────────────────────────────
-- Restore member to member role first
UPDATE organization_members SET role = 'member'
WHERE org_id = '00000000-0000-0000-0000-000000000001'
  AND user_id = '00000000-0000-0000-0000-000000000012';

-- T13: no-owner no puede transferir
SELECT ok(
  (transfer_ownership(
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000012',
    '00000000-0000-0000-0000-000000000011'   -- by: admin (not owner)
  ))->>'error' = 'unauthorized',
  'T13: admin no puede transferir ownership → error=unauthorized'
);

-- T14: no se puede transferir a usuario externo
SELECT ok(
  (transfer_ownership(
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000013',  -- target: outside
    '00000000-0000-0000-0000-000000000010'   -- by: owner
  ))->>'error' = 'new_owner_not_member',
  'T14: transferir a externo → error=new_owner_not_member'
);

-- T15: owner puede transferir a miembro existente
SELECT ok(
  (transfer_ownership(
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000011',  -- new owner: admin
    '00000000-0000-0000-0000-000000000010'   -- current owner
  ))->>'status' = 'ownership_transferred',
  'T15: owner transfiere ownership correctamente → status=ownership_transferred'
);

-- T16: swap atómico — old owner ahora es admin, nuevo es owner
SELECT ok(
  (SELECT count(*) = 2 FROM organization_members
   WHERE org_id = '00000000-0000-0000-0000-000000000001'
     AND (
       (user_id = '00000000-0000-0000-0000-000000000010' AND role = 'admin') OR
       (user_id = '00000000-0000-0000-0000-000000000011' AND role = 'owner')
     )),
  'T16: swap atómico — old_owner=admin, new_owner=owner en DB'
);

SELECT * FROM finish();

ROLLBACK;
