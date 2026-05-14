-- 0024_down.sql — Reverso de 0024_audit_partitioning
-- Revierte particionado: reconstruye audit_log como tabla plana
-- PRECAUCIÓN: ejecutar en ventana de mantenimiento

DROP FUNCTION IF EXISTS ensure_next_audit_partition() CASCADE;
DROP FUNCTION IF EXISTS create_audit_partition(INT, INT) CASCADE;

-- Guardar datos de la tabla particionada
CREATE TABLE audit_log_rollback_backup AS
  SELECT * FROM audit_log;

-- Eliminar tabla particionada (y todas sus particiones en cascada)
DROP TABLE IF EXISTS audit_log CASCADE;

-- Recrear tabla plana original
CREATE TABLE audit_log (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  table_name  TEXT NOT NULL,
  record_id   TEXT NOT NULL,
  action      TEXT NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
  old_data    JSONB,
  new_data    JSONB,
  changed_by  UUID,
  org_id      UUID,
  ip_address  INET,
  session_id  TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_table_record ON audit_log(table_name, record_id);
CREATE INDEX idx_audit_action       ON audit_log(action);
CREATE INDEX idx_audit_org          ON audit_log(org_id) WHERE org_id IS NOT NULL;

-- Restaurar datos
INSERT INTO audit_log SELECT * FROM audit_log_rollback_backup;
DROP TABLE IF EXISTS audit_log_rollback_backup;
