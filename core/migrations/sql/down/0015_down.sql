-- 0015_down.sql — Reverso de 0015_onboarding
-- Elimina onboarding y sistema de invitaciones

DROP FUNCTION IF EXISTS accept_invite(TEXT, UUID) CASCADE;
DROP FUNCTION IF EXISTS invite_member(UUID, UUID, CITEXT, TEXT) CASCADE;
DROP FUNCTION IF EXISTS complete_onboarding_step(UUID, TEXT) CASCADE;
DROP FUNCTION IF EXISTS get_onboarding_status(UUID) CASCADE;
DROP TABLE IF EXISTS member_invites CASCADE;
DROP TABLE IF EXISTS onboarding_progress CASCADE;
