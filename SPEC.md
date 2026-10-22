# docex — Spec v2

Oct 22, 2026 · Dean Hildebrand · supersedes `doc-extraction-api.md` (Oct 16)

## 1. What it is

A multi-tenant JSON API: clients upload a PDF or image, request an extraction against a schema (invoice or receipt in v1), and get structured JSON back via webhook or polling. Every extracted field carries evidence (the source text and page it came from) and deterministic verification checks, so the API says not just *what* it extracted but *whether it can be trusted*.

A thin Hotwire demo page at `/` shows the whole pipeline live, so the project is legible to non-engineers.

### Audiences

| Who | What they look at | What it must show |
| --- | --- | --- |
| Recruiters | Demo page, README top section, 2-minute video | It works, it's polished, it's live |
| Engineers at hiring companies | README trade-offs, code, specs, eval results | Senior judgement: outbox, idempotency, tenancy, state machine, honest LLM handling |

## 2. Scope

### v1 (golden path)

- Organizations, API keys (seeded via rake task), Bearer auth with scopes
- Document upload, list, show, signed download, delete
- Extractions: create, list, show, result
- Built-in schemas `invoice` and `receipt` (versioned, read-only)
- 6-state extraction state machine with retries
- Field evidence + field checks + `needs_review`
- Transactional outbox → signed webhooks with retries and auto-disable
- Idempotency keys on all POSTs
- Cursor pagination, one error shape, prefixed public ids
- Rate limiting (Rails `rate_limit`) and demo caps
- Demo page with samples, code-gated uploads, live timeline, webhook sink
- Eval harness with committed results

### Roadmap (README "If this were real")

- Custom schemas: `POST/PATCH/DELETE /schemas` (new version per PATCH)
- `POST /extractions/:id/cancel`, `POST /extractions/:id/retry` (transitions already exist in the model)
- `GET /events` polling feed, `POST /webhook_deliveries/:id/redeliver`
- `GET/POST/DELETE /api_keys`, `GET /usage`
- Per-organization rate limits (token bucket)
- Postgres row-level security as a second tenancy layer
- Alternative extractors behind `Extractors::Base` (Textract, Tesseract, a Python service)
- Dual-extraction sampling (run 5% twice, measure agreement) as a statistical confidence signal

## 3. Stack

| Concern | Choice |
| --- | --- |
| App | Rails 8, full app (API controllers + one Hotwire page), Ruby 3.3+ |
| Database | PostgreSQL |
| Jobs / pub-sub / cache | Solid Queue, Solid Cable, Solid Cache (no Redis) |
| Files | Active Storage on EU S3-compatible object storage (Hetzner Object Storage or Cloudflare R2) |
| LLM | Claude via the official `anthropic` gem: native PDF/image input + structured outputs. Default model `claude-opus-5-5`; model id is config. |
| Schema validation | `json_schemer` |
| Tests | RSpec, WebMock, FactoryBot |
| CI | GitHub Actions: RSpec, RuboCop (rails-omakase), Brakeman, bundler-audit |
| Deploy | Kamal 2 on a Hetzner VPS (EU region), Postgres as Kamal accessory, kamal-proxy TLS, nightly `pg_dump` to object storage |

## 4. Architecture

```
            ┌──────────────────────┐        ┌───────────────────────┐
  curl ───▶ │ Api::V1::* (JSON,    │        │ Demo* (Turbo Streams, │ ◀─── browser
            │ Bearer, idempotency) │        │ session, demo code)   │
            └──────────┬───────────┘        └───────────┬───────────┘
                       └──────────────┬─────────────────┘
                                      ▼
                    Services (Documents::Upload, Extractions::Create, ...)
                    Current.organization · caps · validation · tenancy
                                      │
                 ┌────────────────────┼─────────────────────┐
                 ▼                    ▼                     ▼
          ExtractionJob ──▶ Extractors::Base       Extraction#transition_to!
                            └ ClaudeExtractor      (row lock → event row)
                                                            │
                                                            ▼
                                           WebhookFanoutJob → WebhookDeliveryJob
                                                            │
                                         client endpoints / built-in /demo/webhook_sink
```

Rules:

- Controllers are thin adapters. Everything the API enforces (tenancy, caps, validation) lives in services, so the demo can't bypass it.
- `ClaudeExtractor` is the only class that talks to Anthropic.
- All tenant data is reached through `Current.organization.<association>`, never `Model.find`.

## 5. Data model

Every tenant-owned table has `organization_id`. All primary keys are UUIDv7 (`SecureRandom.uuid_v7`, assigned in `ApplicationRecord`), `id: :uuid` in migrations.

| Table | Key columns | Relationships | Indexes and constraints |
| --- | --- | --- | --- |
| `organizations` | name, slug, demo (bool), daily_page_cap (nullable) | has many of everything below | unique slug |
| `api_keys` | name, prefix, token_digest, scopes (array), last_used_at, revoked_at | belongs to organization | unique prefix; token stored only as SHA-256 digest |
| `extraction_schemas` | name, document_type, version, json_schema (jsonb), active | belongs to organization (null = built-in) | unique [organization_id, name, version] |
| `documents` | filename, content_type, byte_size, checksum_sha256, page_count, metadata (jsonb), Active Storage file | belongs to organization, api_key (nullable for demo uploads); has many extractions | [organization_id, created_at, id]; [organization_id, checksum_sha256] |
| `extractions` | status, attempts, next_attempt_at, llm_model, prompt_version, error_code, error_message, queued_at, started_at, finished_at | belongs to document, extraction_schema; has one result | [organization_id, status, created_at, id]; check constraint on status and error_code |
| `extraction_results` | data (jsonb), field_evidence (jsonb), field_checks (jsonb), needs_review (bool), raw_response (jsonb), input_tokens, output_tokens | belongs to extraction | unique extraction_id |
| `events` | type, subject_type, subject_id, payload (jsonb), client_visible (bool) | belongs to organization; has many webhook_deliveries | [organization_id, created_at, id] |
| `webhook_endpoints` | url, secret, event_types (array), enabled, consecutive_failures, disabled_at | belongs to organization | [organization_id, enabled] |
| `webhook_deliveries` | status, attempts, response_code, response_body_excerpt, signature_verified (sink only), next_attempt_at, delivered_at | belongs to event, webhook_endpoint | unique [event_id, webhook_endpoint_id]; [status, next_attempt_at] |
| `idempotency_keys` | key, request_fingerprint, response_status, response_body (jsonb), locked_at, expires_at | belongs to organization | unique [organization_id, key] |

Changes from v1 doc: dropped `ocr_blob_key`, `field_confidences`, `overall_confidence`, `rate_limit_per_minute`; added `field_evidence`, `field_checks`, `needs_review`, `raw_response`, `prompt_version`, `next_attempt_at`, `daily_page_cap`, `demo`, `client_visible`.

### Public ids

UUIDs are exposed as type-prefixed base32 strings, encoded in serializers and decoded in controllers by a `PublicId` module:

| Prefix | Model |
| --- | --- |
| `org_` | Organization |
| `key_` | ApiKey |
| `sch_` | ExtractionSchema |
| `doc_` | Document |
| `ext_` | Extraction |
| `evt_` | Event |
| `whe_` | WebhookEndpoint |
| `whd_` | WebhookDelivery |

A malformed id or wrong prefix returns `404 not_found` with `param` set.

## 6. Extraction pipeline

1. `POST /v1/extractions` → `Extractions::Create` checks caps, creates the extraction in `queued`, writes an event, enqueues `ExtractionJob`. Returns `202`.
2. `ExtractionJob` → `transition_to!(:processing)`.
3. `Schemas::ModelSchemaBuilder` derives the **model schema** from the client schema: every leaf becomes `{value, source_text, page}`, all properties required but nullable, `additionalProperties: false`. Verify each JSON Schema keyword used against the structured-outputs supported subset.
4. `ClaudeExtractor` sends the file as a native `document`/`image` content block with the model schema as `output_config.format`. It returns a typed result: success, transient error, refusal, or invalid output.
5. `Extractions::Unwrap` splits output into `data` (values) and `field_evidence` (source text + page). `data` is validated against the client schema with `json_schemer`.
6. `Checks::Runner` runs generic checks and the checks registered for the `document_type`, producing `field_checks` and `needs_review`.
7. Result stored, `transition_to!(:completed)`, event written in the same transaction.

### Prompt and model versioning

`llm_model` and `prompt_version` are stored on every extraction. Prompts live in versioned files (`app/prompts/extraction/v1.md`); bumping the prompt bumps the version.

## 7. Field checks

Checks replace "confidence". Self-reported model confidence is not calibrated, so verification is deterministic and testable.

Each field gets:

```json
"total": { "status": "failed", "reasons": ["subtotal_plus_vat_mismatch"], "expected": 121.00, "actual": 112.00 }
```

Statuses: `verified` (at least one check passed, none failed), `unverified` (no applicable checks), `failed` (at least one check failed). `needs_review` is true when any field is `failed` or a required field is null.

| Check | Applies to |
| --- | --- |
| required-but-null | all schemas |
| type coercion (dates parse, amounts parse) | all schemas |
| `source_text` consistent with `value` | all schemas |
| subtotal + VAT total = total (± 0.01) | invoice, receipt |
| sum of line amounts = subtotal | invoice, receipt |
| line qty × unit price = amount | invoice |
| IBAN mod-97 | invoice |
| EU VAT number format | invoice |
| due date ≥ issue date | invoice |
| ISO 4217 currency | invoice, receipt |

Failed checks never fail the extraction. A total mismatch is a completed extraction with `needs_review: true`.

## 8. Extraction state machine

```
queued ──▶ processing ──▶ completed
  │            │
  │            ├──▶ retrying ──▶ processing   transient: 429, 5xx, timeout. Backoff, max 3 attempts
  │            │
  │            └──▶ failed                    permanent: see error codes
  └──▶ canceled                               only from queued
failed ──▶ queued                             manual retry, resets attempts
```

- All transitions go through `Extraction#transition_to!(new_status)`, which takes a row lock (`lock!`), checks a `TRANSITIONS` hash, raises on an illegal move, updates timestamps, and writes an event in the same transaction.
- Only `completed` and `failed` write client-visible events (`extraction.completed`, `extraction.failed`). The others are internal events shown on the demo timeline.
- Error codes (closed set, DB check constraint): `file_unreadable`, `file_encrypted`, `model_refusal`, `output_invalid`, `upstream_unavailable`, `attempts_exhausted`.
- A model refusal (`stop_reason: "refusal"`) is permanent and is never retried.

## 9. Endpoints (v1)

All under `/v1`, JSON only, `Authorization: Bearer dx_live_<prefix>_<secret>`. Every `POST` accepts `Idempotency-Key`.

| Method | Path | Scope | Purpose | Returns |
| --- | --- | --- | --- | --- |
| POST | `/documents` | documents:write | Upload (multipart, max 20 MB, PDF/PNG/JPEG) | 201 document |
| GET | `/documents` | documents:write | List, cursor paginated, `created_after` filter | 200 list |
| GET | `/documents/:id` | documents:write | Metadata | 200 document |
| GET | `/documents/:id/download` | documents:write | Short-lived signed URL | 302 |
| DELETE | `/documents/:id` | documents:write | Delete file and its extractions, emits `document.deleted` | 204 |
| POST | `/extractions` | extractions:write | Start: `document_id`, `schema_id` | 202 extraction |
| GET | `/extractions` | extractions:read | List, filter by `status`, `document_id` | 200 list |
| GET | `/extractions/:id` | extractions:read | Status, timings, attempts, error | 200 extraction |
| GET | `/extractions/:id/result` | extractions:read | `data`, `field_evidence`, `field_checks`, `needs_review` | 200, 409 if not completed |
| GET | `/schemas` | extractions:read | Built-in schemas | 200 list |
| GET | `/schemas/:id` | extractions:read | Schema with version history | 200 schema |
| GET | `/webhook_endpoints` | webhooks:manage | List | 200 list |
| POST | `/webhook_endpoints` | webhooks:manage | Register URL + event types; secret shown once | 201 endpoint |
| PATCH | `/webhook_endpoints/:id` | webhooks:manage | Change URL, events, re-enable | 200 endpoint |
| DELETE | `/webhook_endpoints/:id` | webhooks:manage | Remove | 204 |
| POST | `/webhook_endpoints/:id/test` | webhooks:manage | Send signed `ping` | 202 |
| GET | `/webhook_endpoints/:id/deliveries` | webhooks:manage | Delivery log | 200 list |

Outside `/v1`: `GET /up`, `GET /docs` (OpenAPI), `/` demo, `/demo/*`.

## 10. Webhooks

- **Outbox:** events are written in the same transaction as the state change. `WebhookFanoutJob` creates one `webhook_delivery` per subscribed, enabled endpoint (unique on [event, endpoint]). Solid Queue lives in the same Postgres, so enqueueing in-transaction would also be possible; the outbox is kept because it is the client-facing event log, the fan-out source, and keeps the design portable to Sidekiq.
- **Event types:** `extraction.completed`, `extraction.failed`, `document.deleted`, `ping`.
- **Payload** carries ids only, never extracted data:

```json
{
  "id": "evt_01J...",
  "type": "extraction.completed",
  "created_at": "2026-10-22T17:02:11Z",
  "data": { "extraction_id": "ext_01J...", "document_id": "doc_01J...", "status": "completed", "needs_review": false }
}
```

- **Signing:** `X-Signature: t=<unix>,v1=<hex>`, where `v1` = HMAC-SHA256 of `"<t>.<raw body>"` with the endpoint secret. Receivers reject anything older than 5 minutes.
- **Retries:** non-2xx or 10 s timeout = failure. Up to 6 attempts, backoff 1 min, 5 min, 30 min, 2 h, 8 h.
- **Auto-disable:** after 20 consecutive failed deliveries; re-enable via `PATCH`.
- **Ordering:** not guaranteed. Clients use `created_at` and treat `id` as an idempotency key.
- **Built-in sink:** the demo org has an endpoint pointing at `/demo/webhook_sink`, which verifies the signature like a real client and records the result for display.

## 11. Cross-cutting rules

| Concern | Approach |
| --- | --- |
| Auth | Look up key by prefix, compare SHA-256 digest with `secure_compare`, check scope per action. Scopes: `documents:write`, `extractions:read`, `extractions:write`, `webhooks:manage`. |
| Tenancy | `Current.organization` from the key (API) or session (demo). Request spec per resource proves org A gets 404 on org B's ids. |
| Rate limiting | Rails `rate_limit` per API key (API) and per IP (demo), backed by Solid Cache. 429 with `Retry-After`. |
| Caps | `organizations.daily_page_cap` enforced in `Extractions::Create`. Demo org has a hard cap; Anthropic Console spend limit as backstop. |
| Idempotency | `Idempotency-Key` stores fingerprint + response for 24 h. Same key and body: replay. Same key, different body: 422. Concurrent duplicate: 409 while `locked_at` is set. |
| Errors | `{"error": {"type": "...", "code": "...", "message": "...", "param": "..."}}`. Types: `authentication`, `permission`, `invalid_request`, `not_found`, `conflict`, `rate_limited`, `internal`. |
| Pagination | Cursor on `(created_at, id)`: `?limit=25&starting_after=<public id>`; response has `data`, `has_more`, `next_cursor`. |
| Versioning | Path versioned `/v1`, serializers per version. |
| Observability | Request id on every response and log line, structured JSON logs, job duration and failure counts. |

## 12. Demo page

- **Samples (default):** 3–4 synthetic documents (clean invoice, phone-photo receipt, invoice with a deliberate total mismatch, Dutch invoice), pre-extracted. Clicking one plays the stored transitions live over Turbo Streams.
- **Uploads:** unlocked by a demo code (env var, rotatable) that sets a session bound to the demo org. Same services, caps and tenancy as the API.
- **Each extraction shows:** live state timeline, document preview next to the extracted fields (failed checks highlighted with reasons), the equivalent `curl` command, and the webhook delivery with signature-verified status from the sink.
- **Retention:** demo documents and results are purged after 24 h by a recurring Solid Queue job. Notice on the page: "Files are deleted after 24 hours. Don't upload sensitive documents."
- **Engineers:** a capped demo API key is published in the README for `curl` use.

## 13. Testing and eval

### CI (no network)

- `FakeExtractor` (success / transient / refusal / invalid output) injected in job and service specs: state machine, retries, error codes.
- `ClaudeExtractor` specs with WebMock and recorded JSON fixtures (API key filtered) for request shape and parsing.
- Pure unit specs for `ModelSchemaBuilder` (snapshot), `Unwrap`, every check, `PublicId`, signing.
- Request specs per endpoint, including tenant isolation and idempotency.
- WebMock blocks all real HTTP.

### Eval harness (manual, costs money)

- `eval/fixtures/<name>/{document.pdf, expected.json}`: 10–15 **synthetic** documents (made-up companies, never real invoices). Same fixtures double as demo samples.
- `bin/rails eval:run` runs the real extractor and reports field-level accuracy (exact for strings, tolerance for amounts, normalized dates), check precision (did `failed` match the planted errors), cost and latency per document.
- Results table committed to the README with `llm_model` and `prompt_version`. Runs via `workflow_dispatch`, never on push.

## 14. Deployment

- Kamal 2, single Hetzner VPS (EU region): web (Puma), job (Solid Queue), Postgres accessory.
- kamal-proxy with Let's Encrypt TLS on a custom domain.
- Active Storage on EU S3-compatible storage.
- Nightly `pg_dump` to object storage via a recurring job or cron on the host, plus a tested restore.
- Secrets via `.kamal/secrets`: `RAILS_MASTER_KEY`, `ANTHROPIC_API_KEY`, storage credentials, `DEMO_CODE`.

## 15. Milestones

Each milestone ends with a Kamal deploy and a README update.

| # | Slice | Live at the end |
| --- | --- | --- |
| M0 | `rails new` (Postgres, Solid trio, UUID primary keys), RSpec, CI green, Kamal on Hetzner with TLS, `/up`, README skeleton | Deployed hello-world; infra risk retired |
| M1 | Orgs, seeded API keys, auth, `PublicId`, error shape, documents, extractions, `ExtractionJob` → `ClaudeExtractor` (invoice), state machine, results | End-to-end extraction via `curl` |
| M2 | Demo page: samples, code-gated upload, Turbo Streams timeline, result view, `curl` snippet; field evidence and checks; receipt schema | Recruiter-facing link: add to CV and LinkedIn |
| M3 | Events outbox, webhook endpoints, signing, delivery and retries, auto-disable, demo sink; idempotency keys; cursor pagination; tenant-isolation specs | The backend depth interviewers probe |
| M4 | Eval harness and README results, rate limits and caps, 24 h purge, backups, OpenAPI `/docs`, README trade-offs with diagram, 2-minute video | Polished and provable |

## 16. Trade-offs (for the README)

| Decision | Chosen | Alternative | Why |
| --- | --- | --- | --- |
| Processing model | Async job, 202 + webhook/polling | Synchronous response | LLM extraction takes 5–60 s; holding requests open ties up Puma threads |
| Extraction | Claude reads the file natively, structured outputs | Textract OCR → LLM | One dependency instead of two, model sees layout, cheaper; adapter keeps OCR pluggable |
| Trust signal | Deterministic field checks + evidence | Model self-reported confidence | Self-reported confidence isn't calibrated; checks are explainable and testable |
| Event delivery | Transactional outbox | `after_commit` enqueue | Enqueue can fail after commit and drop the event; outbox is also the event log |
| Job backend | Solid Queue (no Redis) | Sidekiq + Redis | One fewer service; Rails 8 default; swappable via Active Job if throughput demands |
| Tenant isolation | App-level scoping + isolation specs | Postgres RLS | Simpler to read and test; RLS is the next hardening step |
| IDs | UUIDv7 + prefixed public ids | Bigint / UUIDv4 | Time-ordered index inserts, self-describing ids, wrong-type ids rejected |
| Pagination | Cursor on (created_at, id) | Offset | Stable under inserts; no slow deep offsets |
| Schema changes | Immutable versions | Edit in place | Old results stay reproducible |
| Webhook payload | Ids only | Full data | Sensitive data stays out of delivery logs |
| Demo vs API | Shared services, two adapters | Demo calls API over HTTP / key in browser | No leaked keys, no self-HTTP, one place for rules |
| Hosting | Kamal on Hetzner (EU) | Render / Fly.io | Rails 8 native, fixed low cost, EU data residency |
| Demo access | Samples + code-gated uploads, 24 h purge | Open uploads | Caps cost and abuse; keeps personal data out |

## 17. Open questions

- [ ] Demo samples: replay stored transitions, or re-run live each click?
- [ ] Domain name
- [ ] Default model for the demo org (`claude-opus-5-5` vs a cheaper model) once the eval shows cost and accuracy
- [ ] Which structured-outputs JSON Schema keywords the built-in schemas can rely on (verify against current docs in M1)
