-- 0001_down.sql — Reverso de 0001_init
-- PRECAUCIÓN: elimina extensiones y función base
-- Solo ejecutar si vas a eliminar la base de datos completa

DROP FUNCTION IF EXISTS set_updated_at() CASCADE;
DROP TABLE IF EXISTS schema_versions CASCADE;

-- Las extensiones son globales — solo eliminar si no hay otras dependencias
-- DROP EXTENSION IF EXISTS "uuid-ossp" CASCADE;
-- DROP EXTENSION IF EXISTS "pgcrypto" CASCADE;
-- DROP EXTENSION IF EXISTS "citext" CASCADE;
