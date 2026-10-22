-- Postgres init script for the Kamal db accessory (see config/deploy.yml).
-- The postgres image creates docex_production from POSTGRES_DB; Solid Cache,
-- Solid Queue and Solid Cable each get their own database on the same server.
CREATE DATABASE docex_production_cache;
CREATE DATABASE docex_production_queue;
CREATE DATABASE docex_production_cable;
