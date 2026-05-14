-- rate_limit.sql — rate limiting por org/endpoint [SUP-8]
-- Tabla de configuración + tabla de contadores + función de check

-- 1. Configuración de límites por plan/endpoint
CREATE TABLE rate_limit_config (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  plan         TEXT NOT NULL CHECK (plan IN ('free','starter','pro','enterprise')),
  endpoint     TEXT NOT NULL,          -- ej: 'api/v1/users', '*' = global
  max_requests INT  NOT NULL,          -- máximo de peticiones en la ventana
  window_secs  INT  NOT NULL,          -- tamaño de ventana en segundos
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (plan, endpoint)
);

-- Defaults razonables por plan
INSERT INTO rate_limit_config (plan, endpoint, max_requests, window_secs) VALUES
  ('free',       '*', 100,  60),
  ('starter',    '*', 500,  60),
  ('pro',        '*', 2000, 60),
  ('enterprise', '*', 10000,60)
ON CONFLICT (plan, endpoint) DO NOTHING;

-- 2. Contadores de ventana deslizante por org/endpoint
CREATE TABLE rate_limit_counters (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  org_id       UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  endpoint     TEXT NOT NULL,
  window_start TIMESTAMPTZ NOT NULL,
  request_count INT NOT NULL DEFAULT 1,
  UNIQUE (org_id, endpoint, window_start)
);

CREATE INDEX idx_rl_counters_org_ep ON rate_limit_counters(org_id, endpoint, window_start);

-- 3. Función principal de check
-- Retorna: {allowed, remaining, reset_at, limit}
CREATE OR REPLACE FUNCTION check_rate_limit(
  p_org_id   UUID,
  p_endpoint TEXT
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_plan        TEXT;
  v_max_req     INT;
  v_window_secs INT;
  v_window_start TIMESTAMPTZ;
  v_count       INT;
  v_reset_at    TIMESTAMPTZ;
BEGIN
  -- Obtener plan de la org
  SELECT plan INTO v_plan FROM organizations WHERE id = p_org_id AND is_active = TRUE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('allowed', FALSE, 'reason', 'org_not_found');
  END IF;

  -- Obtener config: endpoint específico, sino wildcard '*'
  SELECT max_requests, window_secs
    INTO v_max_req, v_window_secs
    FROM rate_limit_config
   WHERE plan = v_plan
     AND endpoint IN (p_endpoint, '*')
   ORDER BY CASE WHEN endpoint = p_endpoint THEN 0 ELSE 1 END
   LIMIT 1;

  IF NOT FOUND THEN
    -- Sin config → permitir por defecto
    RETURN jsonb_build_object('allowed', TRUE, 'reason', 'no_config');
  END IF;

  -- Calcular ventana actual
  v_window_start := date_trunc('second', NOW()) -
    ((EXTRACT(EPOCH FROM NOW())::INT % v_window_secs) * INTERVAL '1 second');
  v_reset_at := v_window_start + (v_window_secs * INTERVAL '1 second');

  -- Upsert contador
  INSERT INTO rate_limit_counters (org_id, endpoint, window_start, request_count)
  VALUES (p_org_id, p_endpoint, v_window_start, 1)
  ON CONFLICT (org_id, endpoint, window_start)
    DO UPDATE SET request_count = rate_limit_counters.request_count + 1
  RETURNING request_count INTO v_count;

  RETURN jsonb_build_object(
    'allowed',    v_count <= v_max_req,
    'limit',      v_max_req,
    'remaining',  GREATEST(0, v_max_req - v_count),
    'reset_at',   v_reset_at,
    'plan',       v_plan
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('allowed', TRUE, 'reason', 'error', 'detail', SQLERRM);
END;
$$;
