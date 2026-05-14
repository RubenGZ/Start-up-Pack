-- 0024_audit_partitioning — audit_log particionado por mes [SUP-23]
-- Convierte audit_log a tabla particionada RANGE(created_at)
-- Estrategia: rename → recreate partitioned → attach old data → drop old
-- PRECAUCIÓN: ejecutar en ventana de mantenimiento en producción (lock breve)

-- Paso 1: Guardar datos existentes
CREATE TABLE IF NOT EXISTS audit_log_migration_backup AS
  SELECT * FROM audit_log;

-- Paso 2: Renombrar tabla original
ALTER TABLE audit_log RENAME TO audit_log_unpartitioned;

-- Paso 3: Crear tabla particionada nueva
CREATE TABLE audit_log (
  id          UUID NOT NULL DEFAULT uuid_generate_v4(),
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
) PARTITION BY RANGE (created_at);

-- Paso 4: Partición por defecto para datos sin partición específica
CREATE TABLE audit_log_default
  PARTITION OF audit_log DEFAULT;

-- Paso 5: Función para crear partición mensual
CREATE OR REPLACE FUNCTION create_audit_partition(
  p_year  INT,
  p_month INT
)
RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE
  v_name       TEXT;
  v_start      DATE;
  v_end        DATE;
BEGIN
  v_name  := format('audit_log_%s_%02s', p_year, p_month);
  v_start := make_date(p_year, p_month, 1);
  v_end   := v_start + INTERVAL '1 month';

  IF to_regclass(v_name) IS NOT NULL THEN
    RETURN format('Partición %s ya existe', v_name);
  END IF;

  EXECUTE format(
    'CREATE TABLE %I PARTITION OF audit_log FOR VALUES FROM (%L) TO (%L)',
    v_name, v_start, v_end
  );

  RETURN format('Partición %s creada (%s → %s)', v_name, v_start, v_end);
END;
$$;

-- Paso 6: Crear particiones para los últimos 3 meses + mes actual + 3 meses futuros
DO $$
DECLARE
  v_month DATE;
  v_msg   TEXT;
BEGIN
  -- 3 meses atrás hasta 3 meses adelante
  FOR i IN -3..3 LOOP
    v_month := date_trunc('month', NOW()) + (i || ' months')::INTERVAL;
    SELECT create_audit_partition(
      EXTRACT(YEAR FROM v_month)::INT,
      EXTRACT(MONTH FROM v_month)::INT
    ) INTO v_msg;
    RAISE NOTICE '%', v_msg;
  END LOOP;
END $$;

-- Paso 7: Migrar datos existentes a la tabla particionada
INSERT INTO audit_log
  SELECT * FROM audit_log_unpartitioned;

-- Paso 8: Recrear índices en la tabla particionada (heredados por particiones)
CREATE INDEX idx_audit_table_record ON audit_log(table_name, record_id);
CREATE INDEX idx_audit_action       ON audit_log(action);
CREATE INDEX idx_audit_org          ON audit_log(org_id) WHERE org_id IS NOT NULL;
CREATE INDEX idx_audit_created      ON audit_log(created_at);

-- Paso 9: Función para auto-crear partición del mes siguiente
-- Llamar desde pg_cron: 'SELECT ensure_next_audit_partition();'
CREATE OR REPLACE FUNCTION ensure_next_audit_partition()
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_next DATE;
BEGIN
  v_next := date_trunc('month', NOW()) + INTERVAL '1 month';
  RETURN create_audit_partition(
    EXTRACT(YEAR FROM v_next)::INT,
    EXTRACT(MONTH FROM v_next)::INT
  );
END;
$$;

-- Paso 10: Limpiar tabla original (ya migrada)
DROP TABLE IF EXISTS audit_log_unpartitioned;
DROP TABLE IF EXISTS audit_log_migration_backup;

COMMENT ON TABLE audit_log IS
  'Audit log particionado por mes (RANGE created_at). Usar create_audit_partition() para nuevas particiones.';
COMMENT ON FUNCTION create_audit_partition(INT, INT) IS
  'Crea partición mensual de audit_log. Idempotente. Usar para provisioning de particiones futuras.';
COMMENT ON FUNCTION ensure_next_audit_partition() IS
  'Crea la partición del mes siguiente. Agendar en pg_cron mensualmente.';
