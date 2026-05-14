-- 0003_down.sql — Reverso de 0003_organizations
-- Elimina organizations y organization_members

DROP TABLE IF EXISTS organization_members CASCADE;
DROP TABLE IF EXISTS organizations CASCADE;
