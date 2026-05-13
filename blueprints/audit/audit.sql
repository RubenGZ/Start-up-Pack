-- audit.sql — audit log estructurado universal [SUP-9]
-- Tabla JSONB + trigger genérico aplicable a cualquier tabla

-- 1. Tabla de audit log
CREATE TABLE audit_log (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  table_name  TEXT        NOT NULL,
  record_id   TEXT        NOT NULL,   -- PK del registro afectado (cast a TEXT)
  action      TEXT        NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
  old_data    JSONB,                  -- NULL en INSERT
  new_data    JSONB,                  -- NULL en DELETE
  changed_by  UUID,                  -- user_id si disponible (via app.current_user_id)
  org_id      UUID,                  -- org_id si disponible (via app.current_org_id)
  ip_address  INET,                  -- via app.current_ip
  session_id  TEXT,                  -- via app.current_session_id
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_table_record ON audit_log(table_name, record_id);
CREATE INDEX idx_audit_action       ON audit_log(action);
CREATE INDEX idx_audit_changed_by   ON audit_log(changed_by);
CREATE INDEX idx_audit_org          ON audit_log(org_id);
CREATE INDEX idx_audit_created      ON audit_log(created_at DESC);

-- 2. Función trigger universal
-- Uso: EXECUTE FUNCTION audit_trigger()
-- Lee contexto de sesión vía current_setting (sin error si no existe)
CREATE OR REPLACE FUNCTION audit_trigger()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_record_id  TEXT;
  v_old_data   JSONB;
  v_new_data   JSONB;
  v_user_id    UUID;
  v_org_id     UUID;
  v_ip         INET;
  v_session    TEXT;
BEGIN
  -- Extraer PK: asume columna 'id', fallback a ctid
  BEGIN
    IF TG_OP = 'DELETE' THEN
      v_record_id := OLD.id::TEXT;
    ELSE
      v_record_id := NEW.id::TEXT;
    END IF;
  EXCEPTION WHEN undefined_column THEN
    v_record_id := CASE WHEN TG_OP = 'DELETE'
      THEN OLD::TEXT ELSE NEW::TEXT END;
  END;

  -- Contexto de sesión (set por la app antes de cada operación)
  BEGIN v_user_id := current_setting('app.current_user_id', TRUE)::UUID;
  EXCEPTION WHEN OTHERS THEN v_user_id := NULL; END;
  BEGIN v_org_id  := current_setting('app.current_org_id', TRUE)::UUID;
  EXCEPTION WHEN OTHERS THEN v_org_id  := NULL; END;
  BEGIN v_ip      := current_setting('app.current_ip', TRUE)::INET;
  EXCEPTION WHEN OTHERS THEN v_ip      := NULL; END;
  BEGIN v_session := current_setting('app.current_session_id', TRUE);
  EXCEPTION WHEN OTHERS THEN v_session := NULL; END;

  -- Datos old/new
  IF TG_OP = 'INSERT' THEN
    v_new_data := to_jsonb(NEW);
  ELSIF TG_OP = 'UPDATE' THEN
    v_old_data := to_jsonb(OLD);
    v_new_data := to_jsonb(NEW);
  ELSIF TG_OP = 'DELETE' THEN
    v_old_data := to_jsonb(OLD);
  END IF;

  INSERT INTO audit_log (
    table_name, record_id, action,
    old_data, new_data,
    changed_by, org_id, ip_address, session_id
  ) VALUES (
    TG_TABLE_NAME, v_record_id, TG_OP,
    v_old_data, v_new_data,
    v_user_id, v_org_id, v_ip, v_session
  );

  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

-- 3. Helper: adjuntar audit trigger a una tabla
-- Uso: SELECT attach_audit_trigger('users');
CREATE OR REPLACE FUNCTION attach_audit_trigger(p_table TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE format(
    'CREATE TRIGGER audit_%I
     AFTER INSERT OR UPDATE OR DELETE ON %I
     FOR EACH ROW EXECUTE FUNCTION audit_trigger()',
    p_table, p_table
  );
  RAISE NOTICE '[audit] Trigger adjuntado a tabla: %', p_table;
EXCEPTION WHEN duplicate_object THEN
  RAISE NOTICE '[audit] Trigger ya existe en tabla: %', p_table;
END;
$$;

-- 4. Adjuntar a tablas core del framework
SELECT attach_audit_trigger('users');
SELECT attach_audit_trigger('organizations');
SELECT attach_audit_trigger('subscriptions');
