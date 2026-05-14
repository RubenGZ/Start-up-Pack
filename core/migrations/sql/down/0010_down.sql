-- 0010_down.sql — Reverso de 0010_seed
-- Elimina datos de seed (demo org + admin user)
-- PRECAUCIÓN: solo ejecutar en dev/staging, nunca en producción

DELETE FROM organization_members
  WHERE org_id = 'a0000000-0000-0000-0000-000000000001';

DELETE FROM subscriptions
  WHERE org_id = 'a0000000-0000-0000-0000-000000000001';

DELETE FROM organizations
  WHERE id = 'a0000000-0000-0000-0000-000000000001';

DELETE FROM users
  WHERE id IN (
    'b0000000-0000-0000-0000-000000000001',
    'b0000000-0000-0000-0000-000000000002'
  );
