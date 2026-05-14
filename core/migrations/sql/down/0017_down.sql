-- 0017_down.sql — Reverso de 0017_member_management
-- Elimina funciones de gestión de miembros

DROP FUNCTION IF EXISTS transfer_ownership(UUID, UUID, UUID) CASCADE;
DROP FUNCTION IF EXISTS change_member_role(UUID, UUID, TEXT, UUID) CASCADE;
DROP FUNCTION IF EXISTS remove_member(UUID, UUID, UUID) CASCADE;
DROP FUNCTION IF EXISTS list_org_members(UUID, UUID) CASCADE;
