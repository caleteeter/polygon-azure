-- Postgres bootstrap - For automation

CREATE ROLE grafana WITH PASSWORD 'DB_PASS' LOGIN;
ALTER ROLE grafana SET statement_timeout=60000;
COMMENT ON ROLE grafana IS 'Grafana manager role'

GRANT grafana TO DB_ADMIN;
CREATE DATABASE grafana OWNER grafana
COMMENT ON DATABASE grafana IS 'Grafana database';
REVOKE ALL ON DATABASE grafana TO grafana;
\c grafana
REVOKE ALL ON schema public FROM public;
ALTER SCHEMA public OWNER TO grafana;