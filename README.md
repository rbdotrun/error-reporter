# rbrun-error-reporter

Error reporter SDK + mountable collector engine for Rails apps.

This repo ships **two things** in one gem:

| Role         | Where it lives                              | Who installs it                   |
| ------------ | ------------------------------------------- | --------------------------------- |
| **Engine** (collector) | `app/`, `config/routes.rb`, `db/migrate/` | The operator host (e.g. rbrun) — mounts the engine, persists reports |
| **Ruby SDK** (reporter) | `lib/rbrun_error_reporter/sdk/ruby/`       | Any client Rails app — see [the SDK README](./lib/rbrun_error_reporter/sdk/ruby/README.md) |

The two communicate over a documented HTTP wire protocol — see
[`WIRE_PROTOCOL.md`](./WIRE_PROTOCOL.md). Any SDK in any language
targets the same contract.

This README covers the **operator side**: installing the engine in a
Rails host so it can receive reports from client apps.

### Client SDKs

For installing a client SDK in your app, jump to the README for your
language:

- **Ruby** — [`lib/rbrun_error_reporter/sdk/ruby/README.md`](./lib/rbrun_error_reporter/sdk/ruby/README.md)
- _Python — planned_
- _JavaScript / TypeScript — planned_
- _Go — planned_
- _Other languages_ — implement the
  [HTTP wire protocol](./WIRE_PROTOCOL.md) directly.

---

## Installing the collector engine

The collector is a mountable Rails engine. To host it, a Rails app
adds the gem, mounts the routes, and runs migrations. There is **no
generator and no `rake railties:install:migrations` step** — the
engine auto-appends its migrations into the host's `db:migrate`
paths.

### 1. Add the gem

```ruby
# Gemfile
gem "rbrun-error-reporter",
    git:     "https://github.com/rbdotrun/error-reporter.git",
    branch:  "main",
    require: "rbrun_error_reporter"
```

Then `bundle install`.

### 2. Mount the engine

```ruby
# config/routes.rb
Rails.application.routes.draw do
  # … your routes …

  mount RbRunErrorReporter::Engine => "/error_reporter"
end
```

This adds one route: `POST /error_reporter/errors`. That's where
client apps' HttpSink POSTs land.

### 3. Run migrations

```bash
bin/rails db:migrate
```

Two tables get created:

* **`error_reports`** — captured errors. UUID PK, JSONB payload,
  `fingerprint` (for grouping), `source_app`, `user_id`,
  `workspace_id` (opaque strings — no FK constraints, so the same
  table holds reports from any number of source apps with any kind of
  identifier shape).
* **`ingestion_credentials`** — bearer tokens that authorize POSTs to
  the collector. Plaintext tokens are **never stored**; only SHA256
  digests + the last four characters (for display).

### 4. Configure (optional but recommended)

Create `config/initializers/error_reporter.rb`:

```ruby
RbRunErrorReporter.configure do |c|
  c.environment = Rails.env
  c.release     = ENV["GIT_SHA"]
  c.enabled     = !Rails.env.test?

  # The operator host typically ALSO uses the SDK to report its own
  # errors. Writing directly to error_reports is faster than POSTing
  # to itself over HTTP.
  c.sink =
    if Rails.env.test?
      RbRunErrorReporter::Sdk::Ruby::Sinks::LogSink.new
    else
      RbRunErrorReporter::Sdk::Ruby::Sinks::DatabaseSink.new
    end

  # Optional — last-chance redaction. Return nil to drop a report.
  # c.before_send = ->(payload) { payload }

  # Optional — add app-specific exceptions to ignore. Defaults already
  # include RoutingError, RecordNotFound, InvalidAuthenticityToken.
  # c.ignored_exceptions += %w[YourApp::ExpectedError]
end
```

### 5. Wire up retention (optional but recommended)

The `error_reports` table will grow forever without a retention
policy. Add this to `config/recurring.yml`:

```yaml
production:
  delete_old_error_reports:
    class: "RbRunErrorReporter::DeleteOldErrorReportsJob"
    args:  [{ "older_than_days": 30 }]
    schedule: every day at 3am
```

Adjust `older_than_days` to taste. The job uses `delete_all` so it
runs in O(deleted) without instantiating models.

---

## Issuing ingestion credentials

For each client app that should be allowed to POST errors, the
operator issues a bearer token. Currently this happens in the Rails
console (a self-service UI is a planned follow-up).

```ruby
result = RbRunErrorReporter::IngestionCredential.issue!(name: "appA-prod")
puts result[:token]
# => "rbreport_v1_L4KEGBA_T0hdDj2ZfNAhKxh…"   ← give this to the client team
```

**The plaintext token is shown exactly once** — we store only its
SHA256 digest. If it's lost before being handed off, revoke and
re-issue.

Conventions:

* **One credential per environment per app**, e.g. `appA-prod`,
  `appA-staging`, `worker-prod`. Limits blast radius on rotation.
* **`name` is the default `source_app`** on every report this
  credential authorizes — so it shows up in `error_reports.source_app`
  unless the client overrides it in the payload.
* **Hand off out of band** — 1Password, signed message, whatever
  you'd use for any production secret.

Revoking:

```ruby
RbRunErrorReporter::IngestionCredential.find_by(name: "appA-prod").revoke!
```

The row is kept for audit. Authentication immediately rejects any
token presenting that credential's digest.

---

## Verifying the collector is up

After the engine is mounted and migrations have run:

```bash
# Issue a test credential
bin/rails runner '
  r = RbRunErrorReporter::IngestionCredential.issue!(name: "smoke-test")
  puts "TOKEN=#{r[:token]}"
'
```

Then POST a synthetic error from anywhere with access:

```bash
curl -X POST https://<host>/error_reporter/errors \
  -H "Authorization: Bearer rbreport_v1_..." \
  -H "Content-Type: application/json" \
  -d '{
    "schema_version": 1,
    "exception_class": "Smoke::TestError",
    "message":         "hello from curl",
    "occurred_at":     "2026-05-11T12:00:00.000Z",
    "environment":     "production",
    "source":          "manual"
  }'

# → 202 Accepted {"status":"accepted","id":"..."}
```

Confirm it landed:

```bash
bin/rails runner '
  r = RbRunErrorReporter::ErrorReport.recent.first
  puts r ? "#{r.source_app} #{r.exception_class}: #{r.message}" : "(no rows)"
'
# → smoke-test Smoke::TestError: hello from curl
```

Then clean up the test credential:

```ruby
RbRunErrorReporter::IngestionCredential.find_by(name: "smoke-test").destroy
```

---

## Architecture

```
   Client app (any language)                       Collector (operator host)
   ─────────────────────────                       ─────────────────────────
   capture surface                                 POST /error_reporter/errors
     │                                              ↓ bearer-token auth
     ↓                                              ↓ IngestionCredential lookup
   RbRunErrorReporter.capture(e)  ──────────┐       ↓
     │                                       │      ↓ schema_version, field checks
     ↓ filter                                │      ↓
     ↓ scrub PII                             │      DatabaseSink ──▶ error_reports
     ↓ before_send                           │                       (UUID PK, opaque
     ↓                                       │                        user_id / workspace_id,
   sink ───────────────────────────────────▶ │                        JSONB payload,
     LogSink (test / dev)                    │                        fingerprint for grouping)
     DatabaseSink (collector-host)           │
     HttpSink ─────────────────── HTTPS ─────┘
```

See [`WIRE_PROTOCOL.md`](./WIRE_PROTOCOL.md) for the wire contract,
and per-file comments in `lib/rbrun_error_reporter/sdk/ruby/`
for the implementation tour.

---

## Development

The gem's test suite currently lives in the **rbrun host repository**
at `test/rbrun_error_reporter/`,
`test/{models,controllers,jobs}/rb_run_error_reporter/`, and
`test/integration/error_reporter_*.rb`. Run via `dip test` from
rbrun. These tests exercise the gem against a real Rails app +
PostgreSQL — closer to the real deployment than a dummy app would
be.

An in-repo suite (combustion-based or with a `test/dummy/` Rails app)
is on the roadmap. Until then, changes here should be developed
against a local checkout
(`gem "rbrun-error-reporter", path: "../error-reporter"` in rbrun's
Gemfile), validated with `dip test` in rbrun, and pushed to this
repo's `main` so rbrun's `Gemfile.lock` can pull the new SHA via
`bundle update rbrun-error-reporter`.

---

## Roadmap

* In-repo test suite (combustion or `test/dummy/`) so the gem is
  testable in isolation, with CI on GitHub Actions
* Admin UI under the engine mount for browsing / grouping reports
* Self-service credential management UI (replaces the console
  `issue!` step)
* Per-source rate limiting on the collector
* Sibling SDKs in Python and JavaScript (same wire format)
* Split the gem into separate SDK and collector packages once we have
  more than one consumer
