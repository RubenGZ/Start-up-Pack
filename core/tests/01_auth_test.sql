-- 01_auth_test.sql — pgTAP: upsert_oauth_user + session expiry
-- Suite: auth module
-- Verifica: (1) upsert_oauth_user no duplica registros, (2) sesiones caducan correctamente

BEGIN;

SELECT plan(9);

-- ── Fixtures ────────────────────────────────────────────────────────────────
-- Org demo (requiere seed o insert manual)
INSERT INTO organizations (id, name, slug, plan)
VALUES ('00000000-0000-0000-0000-000000000001', 'Test Org', 'test-org', 'free')
ON CONFLICT (id) DO NOTHING;

-- ── T1: upsert crea usuario nuevo ───────────────────────────────────────────
SELECT ok(
  (SELECT count(*) = 0 FROM users WHERE email = 'oauth_test@example.com'),
  'T1: no existe usuario previo con email oauth_test@example.com'
);

-- Primera llamada: debe crear usuario
SELECT ok(
  (SELECT user_id IS NOT NULL
   FROM upsert_oauth_user('google','g_001','oauth_test@example.com','Test User',NULL,NULL,NULL)),
  'T2: upsert_oauth_user devuelve user_id no nulo'
);

SELECT ok(
  (SELECT is_new_user = TRUE
   FROM upsert_oauth_user('google','g_001','oauth_test@example.com','Test User',NULL,NULL,NULL)
   LIMIT 1),
  'T3: is_new_user = TRUE en primera llamada'
);

-- ── T2: segunda llamada NO duplica usuario ──────────────────────────────────
-- Segunda llamada con mismo provider_user_id
SELECT ok(
  (SELECT is_new_user = FALSE
   FROM upsert_oauth_user('google','g_001','oauth_test@example.com','Test User Updated',NULL,NULL,NULL)
   LIMIT 1),
  'T4: is_new_user = FALSE en segunda llamada (no duplica usuario)'
);

SELECT ok(
  (SELECT count(*) = 1 FROM users WHERE email = 'oauth_test@example.com'),
  'T5: exactamente 1 fila en users para oauth_test@example.com tras 2 upserts'
);

SELECT ok(
  (SELECT count(*) = 1 FROM oauth_accounts WHERE provider = 'google' AND provider_user_id = 'g_001'),
  'T6: exactamente 1 fila en oauth_accounts (no duplicado)'
);

-- ── T3: tokens distintos por cada llamada ────────────────────────────────────
DO $$
DECLARE
  t1 TEXT; t2 TEXT;
BEGIN
  SELECT session_token INTO t1 FROM upsert_oauth_user('google','g_001','oauth_test@example.com',NULL,NULL,NULL,NULL);
  SELECT session_token INTO t2 FROM upsert_oauth_user('google','g_001','oauth_test@example.com',NULL,NULL,NULL,NULL);
  IF t1 = t2 THEN
    RAISE EXCEPTION 'tokens duplicados: % = %', t1, t2;
  END IF;
END $$;

SELECT ok(TRUE, 'T7: cada llamada genera session_token distinto');

-- ── T4: sesiones tienen expires_at en el futuro (30 días) ───────────────────
SELECT ok(
  (SELECT expires_at > NOW() + INTERVAL '29 days'
   FROM sessions
   WHERE user_id = (SELECT id FROM users WHERE email = 'oauth_test@example.com')
   ORDER BY created_at DESC
   LIMIT 1),
  'T8: sesión tiene expires_at > NOW() + 29 days (correcto: 30 días)'
);

-- ── T5: cleanup_expired_auth elimina sesiones vencidas ──────────────────────
-- Insertar sesión expirada artificialmente
INSERT INTO sessions (user_id, token_hash, expires_at)
SELECT id, 'expired_hash_' || gen_random_uuid()::text, NOW() - INTERVAL '1 minute'
FROM users WHERE email = 'oauth_test@example.com';

SELECT ok(
  (SELECT count(*) > 0 FROM sessions WHERE expires_at < NOW()
   AND user_id = (SELECT id FROM users WHERE email = 'oauth_test@example.com')),
  'T9-pre: existe sesión expirada antes de cleanup'
);

PERFORM cleanup_expired_auth();

SELECT ok(
  (SELECT count(*) = 0 FROM sessions WHERE expires_at < NOW()
   AND user_id = (SELECT id FROM users WHERE email = 'oauth_test@example.com')),
  'T9: cleanup_expired_auth() elimina sesiones vencidas'
);

SELECT * FROM finish();

ROLLBACK;
