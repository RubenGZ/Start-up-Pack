-- pg_cron_init.sql — ejecutado por Docker en primer arranque
-- Instala pg_cron en la DB de desarrollo antes que las migrations
CREATE EXTENSION IF NOT EXISTS pg_cron;
GRANT USAGE ON SCHEMA cron TO hydra;
