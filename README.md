# rbrun-error-reporter

In-house error reporter for rbrun and the apps that talk to it.

Two roles in one package:

* **Ruby SDK** — drop into any Rails app to capture unhandled
  exceptions (web requests, background jobs, scripts, scheduled tasks)
  and forward them to a sink. Local-file logging, local database, or
  HTTP to a central collector.
* **Mountable collector engine** — receive HTTP-reported errors from
  external apps, persist them in `error_reports`, expose them for
  later browsing / alerting. Mounted in rbrun at `/error_reporter`.

Future SDKs (Python, JavaScript, Go, …) will speak the same
HTTP wire format. See [`WIRE_PROTOCOL.md`](./WIRE_PROTOCOL.md) for the
cross-language contract.

---

## Onboarding a new client app

There are two sides to onboarding: **the operator** (whoever runs the
collector — currently us, rbrun) issues a credential, **the client app
team** installs the SDK with that credential.

### Operator side — issue an ingestion credential

For now, we (the operator) generate the credential and hand it to the
client team out of band (1Password, signed message, whatever you'd use
for any production secret). A self-service UI is a future feature.

In a Rails console on the collector host:

```ruby
result = RbRunErrorReporter::IngestionCredential.issue!(name: "appA-prod")
# => { credential: #<…>, token: "rbreport_v1_…" }

puts result[:token]
# => "rbreport_v1_L4KEGBA_T0hdDj2ZfNAhKxh…"   ← give THIS to the client
```

Important:

* The plaintext token is returned **once**. We store only its SHA256
  digest plus the last four characters (for display). If the operator
  loses it before handing it over, revoke and re-issue.
* `name` is the human label that shows up as the default `source_app`
  on every error this credential reports. Use the deployment as the
  name: `appA-prod`, `appA-staging`, `worker-prod`, …. One credential
  per environment per app keeps blast radius small at rotation time.
* Revoke when an app is decommissioned or a key is suspected leaked:

  ```ruby
  RbRunErrorReporter::IngestionCredential.find_by(name: "appA-prod").revoke!
  ```

  Authentication immediately rejects any token presenting that
  credential's digest. The row is kept for audit.

### Client side — install the SDK in a Rails app

The client app needs three things: the gem in its `Gemfile`, an
initializer that points at the collector, and (for jobs / requests)
nothing else — capture happens automatically.

1. **Gemfile**

   ```ruby
   # Gemfile
   gem "rbrun-error-reporter",
       git:     "https://github.com/rbdotrun/error-reporter.git",
       branch:  "main",
       require: "rbrun_error_reporter"
   ```

   To pin a release once we start tagging them:

   ```ruby
   gem "rbrun-error-reporter",
       git:     "https://github.com/rbdotrun/error-reporter.git",
       tag:     "v0.1.0",
       require: "rbrun_error_reporter"
   ```

   Then `bundle install`.

2. **Configure the sink** at `config/initializers/error_reporter.rb`:

   ```ruby
   RbRunErrorReporter.configure do |c|
     c.environment = Rails.env
     c.release     = ENV["GIT_SHA"]
     c.enabled     = !Rails.env.test?

     # Point at the rbrun collector. Endpoint is configurable so we
     # can move the collector later without touching client apps.
     c.sink = RbRunErrorReporter::Sdk::Ruby::Sinks::HttpSink.new(
       endpoint: ENV.fetch("ERROR_REPORTER_ENDPOINT"),    # e.g. "https://rbrun.example/error_reporter/errors"
       token:    ENV.fetch("ERROR_REPORTER_TOKEN")        # the rbreport_v1_… string from the operator
     )

     # Optional — drop a payload before send, or scrub extras:
     # c.before_send = ->(payload) { payload }
     #
     # Optional — add app-specific exceptions to ignore (default list
     # already excludes RoutingError, RecordNotFound, InvalidAuthenticityToken):
     # c.ignored_exceptions += %w[MyApp::ExpectedNoiseError]
   end
   ```

3. **That's it.** The engine wires:

   * Rack middleware → catches unhandled web request errors
   * `ActiveJob::Base` perform hook → catches every failed job
   * `Rails.error.subscribe` → catches `rescue_from`, ActionCable,
     ActiveRecord async query errors
   * `at_exit` → catches Rake / `bin/rails runner` / script crashes

   For manual capture in `rescue` blocks:

   ```ruby
   begin
     risky_thing
   rescue => e
     RbRunErrorReporter.capture(e, my_extra: "context")
     # decide whether to swallow or re-raise
   end
   ```

4. **Carry user/workspace context into jobs** — _optional but
   recommended._ The SDK's `PayloadBuilder` auto-attaches
   `Current.user` and `Current.workspace` to every report. For web
   requests these are usually set by the auth layer already; for
   background jobs, add this to your `ApplicationJob`:

   ```ruby
   class ApplicationJob < ActiveJob::Base
     before_perform do |job|
       job.arguments.each do |arg|
         case arg
         when ::User      then ::Current.user      = arg
         when ::Workspace then ::Current.workspace = arg
         end
       end
     end
   end
   ```

### Client side — non-Ruby app

The SDK is currently Ruby-only. Other-language clients POST directly
to the collector following the wire protocol — see
[`WIRE_PROTOCOL.md`](./WIRE_PROTOCOL.md) for the full schema,
headers, and response codes. Minimum viable payload:

```
POST <collector>/error_reporter/errors
Authorization: Bearer rbreport_v1_…
Content-Type: application/json

{
  "schema_version": 1,
  "exception_class": "MyApp.SomeError",
  "message":         "thing exploded",
  "occurred_at":     "2026-05-11T12:34:56.789Z",
  "environment":     "production",
  "source":          "manual"
}
```

→ `202 Accepted { "status": "accepted", "id": "<uuid>" }`

---

## Verifying it works

After the client app boots with the SDK configured:

```bash
bin/rails runner 'raise "smoke test"'
```

then on the collector (rbrun) side:

```bash
bin/rails runner '
  r = RbRunErrorReporter::ErrorReport.recent.first
  puts r ? "#{r.source_app} #{r.exception_class}: #{r.message}" : "(no rows)"
'
```

You should see `appA-prod RuntimeError: smoke test` (or similar). If
you don't:

* Is `RbRunErrorReporter.configuration.enabled` true on the client?
  (Default is `!Rails.env.test?` — make sure you're not running in
  test env.)
* Is the bearer token correct and not revoked? Tail the collector
  logs — invalid bearer logs `401 unauthorized`.
* Is the endpoint reachable from the client? An HttpSink network
  error logs a single line at warn level and drops the report;
  it never raises or blocks the request thread.

---

## Architecture (1-screen summary)

```
   Client app (any language)                       Collector (rbrun)
   ─────────────────────────                       ──────────────────
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
and the per-file comments in `lib/rbrun_error_reporter/sdk/ruby/`
for the implementation tour.

---

## Development

The gem's test suite currently lives in the **rbrun host
repository** at `test/rbrun_error_reporter/`,
`test/{models,controllers,jobs}/rb_run_error_reporter/`, and
`test/integration/error_reporter_*.rb`. Run via `dip test` from
rbrun. These tests exercise the gem against a real Rails app +
PostgreSQL — closer to the real deployment than a dummy app would
be.

An in-repo suite (combustion-based or with a `test/dummy/` Rails
app) is on the roadmap so this gem can be tested in isolation — see
below. Until then, changes here should be developed against a local
checkout (`gem "rbrun-error-reporter", path: "../error-reporter"` in
rbrun's Gemfile), validated with `dip test` in rbrun, and pushed to
this repo's `main` so rbrun's `Gemfile.lock` can pull the new SHA
via `bundle update rbrun-error-reporter`.

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
