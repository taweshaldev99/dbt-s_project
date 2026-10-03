-- setup_bronze.sql
-- Moves the six source tables from the "public" schema (where the provided
-- insert_to_postgres.py / insert.sql create them) into the "bronze" schema that
-- the dbt project reads from. The provided files are NOT modified.
--
-- Safe to run more than once: tables already in bronze are left alone.
-- Foreign keys, indexes and constraints move with their tables.
-- Run it in one session, e.g.:  psql -f source_data/setup_bronze.sql

CREATE SCHEMA IF NOT EXISTS bronze;

DO $$
DECLARE
    t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['customer', 'branch', 'product', 'account', 'card', 'hist_transactional']
    LOOP
        IF to_regclass('public.' || quote_ident(t)) IS NOT NULL THEN
            IF to_regclass('bronze.' || quote_ident(t)) IS NULL THEN
                EXECUTE format('ALTER TABLE public.%I SET SCHEMA bronze', t);
                RAISE NOTICE 'moved public.% to bronze.%', t, t;
            ELSE
                RAISE EXCEPTION
                    'both public.% and bronze.% exist. Drop one of them (usually: DROP SCHEMA bronze CASCADE, then reload) and run this script again.',
                    t, t;
            END IF;
        END IF;
    END LOOP;
END
$$;

-- Check: all six tables should now be in bronze and none left in public.
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_name IN ('customer', 'branch', 'product', 'account', 'card', 'hist_transactional')
  AND table_schema IN ('public', 'bronze')
ORDER BY table_schema, table_name;