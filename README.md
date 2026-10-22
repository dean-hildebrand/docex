# docex

A multi-tenant document extraction API built with Rails 8. Upload a PDF or image of an invoice or receipt, and get structured JSON back, where every field carries the source text it came from and deterministic verification checks.

> **Status:** M0 (infrastructure). The live demo arrives in M2. See [SPEC.md](SPEC.md) for the full design.

## Stack

Rails 8.1 · PostgreSQL · Solid Queue / Cable / Cache (no Redis) · Hotwire · Claude (native PDF input + structured outputs) · RSpec · Kamal 2 on Hetzner

## Architecture

_Diagram coming in M4. Until then, see [SPEC.md §4](SPEC.md#4-architecture)._

## Running locally

Requirements: Ruby 3.4.10 (see `.ruby-version`), PostgreSQL 17.

```sh
bin/setup        # installs gems, prepares the database, starts the server
bin/rspec        # runs the test suite
bin/ci           # runs everything CI runs: lint, security scans, specs
```

## Deploying

Deploys with [Kamal 2](https://kamal-deploy.org) to a single Hetzner VPS, with Postgres as a Kamal accessory.

1. Replace `SERVER_IP` and `APP_DOMAIN` in `config/deploy.yml`.
2. `export DOCEX_DATABASE_PASSWORD=...` (a long random string).
3. `bin/kamal setup` for the first deploy, then `bin/kamal deploy`.

## Trade-offs

_Written up as choice, alternative, and why in M4. Draft in [SPEC.md §16](SPEC.md#16-trade-offs-for-the-readme)._
