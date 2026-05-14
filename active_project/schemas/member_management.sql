-- member_management.sql — gestión de miembros por org [SUP-13]
-- Funciones: list_org_members, remove_member, change_member_role, transfer_ownership

-- 1. list_org_members — lista miembros con info de usuario
CREATE OR REPLACE FUNCTION list_org_members(
  p_org_id     UUID,
  p_caller_id  UUID
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_members JSONB;
BEGIN
  -- Solo miembros de la org pueden ver el listado
  IF NOT EXISTS (
    SELECT 1 FROM organization_members
    WHERE org_id = p_org_id AND user_id = p_caller_id
  ) THEN
    RETURN jsonb_build_object('error', 'unauthorized');
  END IF;

  SELECT jsonb_agg(
    jsonb_build_object(
      'user_id',  u.id,
      'email',    u.email,
      'name',     u.name,
      'role',     om.role,
      'joined_at', om.joined_at
    ) ORDER BY
      CASE om.role WHEN 'owner' THEN 0 WHEN 'admin' THEN 1 ELSE 2 END,
      om.joined_at
  )
  INTO v_members
  FROM organization_members om
  JOIN users u ON u.id = om.user_id
  WHERE om.org_id = p_org_id;

  RETURN jsonb_build_object(
    'org_id',  p_org_id,
    'count',   jsonb_array_length(COALESCE(v_members, '[]'::JSONB)),
    'members', COALESCE(v_members, '[]'::JSONB)
  );
END;
$$;

-- 2. remove_member — expulsa miembro (owner/admin pueden; no puede removerse el owner)
CREATE OR REPLACE FUNCTION remove_member(
  p_org_id      UUID,
  p_target_id   UUID,
  p_removed_by  UUID
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_caller_role TEXT;
  v_target_role TEXT;
BEGIN
  -- Obtener roles
  SELECT role INTO v_caller_role FROM organization_members
  WHERE org_id = p_org_id AND user_id = p_removed_by;

  SELECT role INTO v_target_role FROM organization_members
  WHERE org_id = p_org_id AND user_id = p_target_id;

  -- Validaciones
  IF v_caller_role IS NULL THEN
    RETURN jsonb_build_object('error', 'caller_not_member');
  END IF;

  IF v_target_role IS NULL THEN
    RETURN jsonb_build_object('error', 'target_not_member');
  END IF;

  IF v_target_role = 'owner' THEN
    RETURN jsonb_build_object('error', 'cannot_remove_owner');
  END IF;

  -- Solo owner/admin pueden remover; admin no puede remover otro admin
  IF v_caller_role NOT IN ('owner', 'admin') THEN
    RETURN jsonb_build_object('error', 'unauthorized');
  END IF;

  IF v_caller_role = 'admin' AND v_target_role = 'admin' THEN
    RETURN jsonb_build_object('error', 'admin_cannot_remove_admin');
  END IF;

  -- Remover
  DELETE FROM organization_members
  WHERE org_id = p_org_id AND user_id = p_target_id;

  RETURN jsonb_build_object(
    'status',     'removed',
    'org_id',     p_org_id,
    'removed_id', p_target_id
  );
END;
$$;

-- 3. change_member_role — cambia rol (solo owner puede; no puede cambiar al owner)
CREATE OR REPLACE FUNCTION change_member_role(
  p_org_id      UUID,
  p_target_id   UUID,
  p_new_role    TEXT,
  p_changed_by  UUID
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_caller_role TEXT;
  v_target_role TEXT;
  v_valid_roles TEXT[] := ARRAY['admin','member'];
BEGIN
  -- Validar rol solicitado
  IF NOT (p_new_role = ANY(v_valid_roles)) THEN
    RETURN jsonb_build_object('error', 'invalid_role', 'valid', v_valid_roles);
  END IF;

  SELECT role INTO v_caller_role FROM organization_members
  WHERE org_id = p_org_id AND user_id = p_changed_by;

  SELECT role INTO v_target_role FROM organization_members
  WHERE org_id = p_org_id AND user_id = p_target_id;

  IF v_caller_role IS NULL THEN
    RETURN jsonb_build_object('error', 'caller_not_member');
  END IF;

  IF v_target_role IS NULL THEN
    RETURN jsonb_build_object('error', 'target_not_member');
  END IF;

  -- Solo owner puede cambiar roles
  IF v_caller_role != 'owner' THEN
    RETURN jsonb_build_object('error', 'unauthorized', 'required', 'owner');
  END IF;

  -- No se puede cambiar el rol del owner directamente (usar transfer_ownership)
  IF v_target_role = 'owner' THEN
    RETURN jsonb_build_object('error', 'use_transfer_ownership_instead');
  END IF;

  UPDATE organization_members
  SET role = p_new_role
  WHERE org_id = p_org_id AND user_id = p_target_id;

  RETURN jsonb_build_object(
    'status',     'role_changed',
    'org_id',     p_org_id,
    'user_id',    p_target_id,
    'old_role',   v_target_role,
    'new_role',   p_new_role
  );
END;
$$;

-- 4. transfer_ownership — transfiere ownership a otro miembro
CREATE OR REPLACE FUNCTION transfer_ownership(
  p_org_id      UUID,
  p_new_owner   UUID,
  p_current_owner UUID
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_caller_role  TEXT;
  v_target_role  TEXT;
BEGIN
  SELECT role INTO v_caller_role FROM organization_members
  WHERE org_id = p_org_id AND user_id = p_current_owner;

  SELECT role INTO v_target_role FROM organization_members
  WHERE org_id = p_org_id AND user_id = p_new_owner;

  IF v_caller_role != 'owner' THEN
    RETURN jsonb_build_object('error', 'unauthorized', 'required', 'owner');
  END IF;

  IF v_target_role IS NULL THEN
    RETURN jsonb_build_object('error', 'new_owner_not_member');
  END IF;

  -- Atomic swap en una transacción
  UPDATE organization_members SET role = 'admin'
  WHERE org_id = p_org_id AND user_id = p_current_owner;

  UPDATE organization_members SET role = 'owner'
  WHERE org_id = p_org_id AND user_id = p_new_owner;

  RETURN jsonb_build_object(
    'status',        'ownership_transferred',
    'org_id',        p_org_id,
    'new_owner',     p_new_owner,
    'previous_owner', p_current_owner
  );
END;
$$;
