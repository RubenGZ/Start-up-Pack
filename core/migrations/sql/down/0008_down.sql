-- 0008_down.sql — Reverso de 0008_helpers
-- Elimina funciones utilitarias compartidas
-- PRECAUCIÓN: set_updated_at es usada por triggers — ejecutar solo tras drops de tablas

DROP FUNCTION IF EXISTS slugify(TEXT) CASCADE;
DROP FUNCTION IF EXISTS generate_short_id() CASCADE;
DROP FUNCTION IF EXISTS now_utc() CASCADE;
