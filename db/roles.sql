-- Roles for the notifications database. Locally a superuser runs this; on Neon
-- `notifications-db provision` creates the same roles through the migrator.
--
-- notifications_migrator  owns the schema and runs migrations only.
-- notifications_api       the API at runtime: no superuser, no BYPASSRLS, owns nothing.

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'notifications_migrator') THEN
        CREATE ROLE notifications_migrator LOGIN NOSUPERUSER NOCREATEROLE NOBYPASSRLS;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'notifications_api') THEN
        CREATE ROLE notifications_api LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS NOINHERIT;
    END IF;
END
$$;
