-- 04_rate_limit_test.sql — pgTAP: rate limiting module
-- Suite: check_rate_limit · sliding window · plan limits · cleanup
-- Verifica: allowed/remaining/reset_at correctos, plan escalation, org_not_found

BEGIN;

SELECT plan(12);

-- ── Fixtures ────────────────────────────────────────────────────────────────
INSERT INTO organizations (id, name, slug, plan)
VALUES
  ('00000000-0000-0000-0000-000000000001', 'Free Org',        'free-org',    'free'),
  ('00000000-0000-0000-0000-000000000002', 'Pro Org',         'pro-org',     'pro'),
  ('00000000-0000-0000-0000-000000000003', 'Enterprise Org',  'ent-org',     'enterprise')
ON CONFLICT (id) DO NOTHING;

-- Límite bajo personalizado para testing (max 3 en 60s)
INSERT INTO rate_limit_config (plan, endpoint, max_requests, window_secs)
VALUES ('free', 'test/endpoint', 3, 60)
ON CONFLICT (plan, endpoint) DO UPDATE SET max_requests = 3;

-- ── BLOQUE 1: org_not_found ──────────────────────────────────────────────────

SELECT ok(
  (check_rate_limit(
    'deadbeef-dead-dead-dead-deadbeefbeef'::UUID,
    'api/v1/test'
  ))->>'allowed' = 'false',
  'T1: org inexistente → allowed=false, reason=org_not_found'
);

SELECT ok(
  (check_rate_limit(
    'deadbeef-dead-dead-dead-deadbeefbeef'::UUID,
    'api/v1/test'
  ))->>'reason' = 'org_not_found',
  'T2: org inexistente → reason=org_not_found'
);

-- ── BLOQUE 2: sliding window — free plan con límite custom ──────────────────

-- Primera request: allowed=true, remaining=2
SELECT ok(
  (check_rate_limit(
    '00000000-0000-0000-0000-000000000001',
    'test/endpoint'
  ))->>'allowed' = 'true',
  'T3: primera request → allowed=true'
);

SELECT ok(
  ((check_rate_limit(
    '00000000-0000-0000-0000-000000000001',
    'test/endpoint'
  ))->>'remaining')::INT >= 0,
  'T4: remaining es >= 0'
);

-- Consumir hasta el límite (2 requests más = total 4 > límite de 3)
-- Nota: el contador ya tiene 2 del T3+T4, la siguiente será la 3ra (allowed), la 4ta bloqueada
PERFORM check_rate_limit('00000000-0000-0000-0000-000000000001', 'test/endpoint'); -- req 3
PERFORM check_rate_limit('00000000-0000-0000-0000-000000000001', 'test/endpoint'); -- req 4 (sobre límite)

SELECT ok(
  (check_rate_limit(
    '00000000-0000-0000-0000-000000000001',
    'test/endpoint'
  ))->>'allowed' = 'false',
  'T5: 5ta request sobre límite (max=3) → allowed=false'
);

SELECT ok(
  ((check_rate_limit(
    '00000000-0000-0000-0000-000000000001',
    'test/endpoint'
  ))->>'remaining')::INT = 0,
  'T6: remaining=0 cuando límite superado'
);

-- ── BLOQUE 3: respuesta incluye campos requeridos ───────────────────────────

DO $$
DECLARE result JSONB;
BEGIN
  result := check_rate_limit('00000000-0000-0000-0000-000000000002', 'api/v1/data');
  IF result->>'reset_at' IS NULL THEN
    RAISE EXCEPTION 'reset_at is null in result: %', result;
  END IF;
  IF result->>'limit' IS NULL THEN
    RAISE EXCEPTION 'limit is null in result: %', result;
  END IF;
  IF result->>'plan' IS NULL THEN
    RAISE EXCEPTION 'plan is null in result: %', result;
  END IF;
END $$;

SELECT ok(TRUE, 'T7: resultado incluye reset_at, limit y plan');

-- ── BLOQUE 4: plan escalation — pro tiene límites más altos que free ─────────

SELECT ok(
  ((check_rate_limit('00000000-0000-0000-0000-000000000002', '*'))->>'limit')::INT >
  ((check_rate_limit('00000000-0000-0000-0000-000000000001', '*'))->>'limit')::INT,
  'T8: pro plan tiene limit mayor que free plan en endpoint *'
);

SELECT ok(
  ((check_rate_limit('00000000-0000-0000-0000-000000000003', '*'))->>'limit')::INT >=
  ((check_rate_limit('00000000-0000-0000-0000-000000000002', '*'))->>'limit')::INT,
  'T9: enterprise plan tiene limit >= pro plan'
);

-- ── BLOQUE 5: endpoint sin config → allowed por defecto ─────────────────────

SELECT ok(
  (check_rate_limit(
    '00000000-0000-0000-0000-000000000001',
    'endpoint/sin/config/especifica'
  ))->>'allowed' = 'true',
  'T10: endpoint sin config específica → fallback al wildcard * (allowed=true)'
);

-- ── BLOQUE 6: cleanup_rate_limit_counters ────────────────────────────────────

-- Insertar contador antiguo (hace 2 horas)
INSERT INTO rate_limit_counters (org_id, endpoint, window_start, request_count)
VALUES (
  '00000000-0000-0000-0000-000000000001',
  'old/endpoint',
  NOW() - INTERVAL '2 hours',
  99
) ON CONFLICT DO NOTHING;

SELECT ok(
  (SELECT count(*) > 0 FROM rate_limit_counters
   WHERE endpoint = 'old/endpoint'
     AND window_start < NOW() - INTERVAL '1 hour'),
  'T11-pre: existe contador antiguo antes de cleanup'
);

PERFORM cleanup_rate_limit_counters(1);  -- mantener solo última 1 hora

SELECT ok(
  (SELECT count(*) = 0 FROM rate_limit_counters
   WHERE endpoint = 'old/endpoint'
     AND window_start < NOW() - INTERVAL '1 hour'),
  'T12: cleanup_rate_limit_counters elimina contadores > 1h'
);

SELECT * FROM finish();

ROLLBACK;
