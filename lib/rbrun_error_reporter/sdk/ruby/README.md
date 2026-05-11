# rbrun-error-reporter — Ruby SDK

The Ruby SDK of [rbrun-error-reporter](../../../../README.md). Drop
this into any Rails app to capture unhandled exceptions and forward
them to a collector.

For non-Ruby clients, skip this file and implement the
[wire protocol](../../../../WIRE_PROTOCOL.md) directly.
For installing the **collector** (the receiving side), see the
[repo root README](../../../../README.md).

---

## Install

### 1. Add the gem

```ruby
# Gemfile
gem "rbrun-error-reporter",
    git:     "https://github.com/rbdotrun/error-reporter.git",
    branch:  "main",
    require: "rbrun_error_reporter"
```

Or pin a tagged release:

```ruby
gem "rbrun-error-reporter",
    git:     "https://github.com/rbdotrun/error-reporter.git",
    tag:     "v0.1.0",
    require: "rbrun_error_reporter"
```

Then `bundle install`.

### 2. Get a credential from the collector operator

You need two values from whoever runs the collector:

* The **endpoint** — e.g. `https://rbrun.example/error_reporter/errors`
* A **bearer token** — e.g. `rbreport_v1_…`

The operator issues these via
`RbRunErrorReporter::IngestionCredential.issue!(name: "<your-app>-<env>")`.
The token is returned exactly once at issue time and handed to you out
of band. Store it like any other production secret (env var, Rails
credentials, your secret manager of choice).

### 3. Configure the SDK

Create `config/initializers/error_reporter.rb`:

```ruby
RbRunErrorReporter.configure do |c|
  c.environment = Rails.env
  c.release     = ENV["GIT_SHA"]
  c.enabled     = !Rails.env.test?

  c.sink = RbRunErrorReporter::Sdk::Ruby::Sinks::HttpSink.new(
    endpoint: ENV.fetch("ERROR_REPORTER_ENDPOINT"),
    token:    ENV.fetch("ERROR_REPORTER_TOKEN")
  )

  # Optional — last-chance redaction. Return nil to drop a report.
  # c.before_send = ->(payload) { payload }
  #
  # Optional — add app-specific exceptions to ignore. The defaults
  # already include RoutingError, RecordNotFound, and
  # InvalidAuthenticityToken.
  # c.ignored_exceptions += %w[YourApp::ExpectedNoiseError]
end
```

### 4. That's it

Five capture hooks are wired automatically by the engine — no other
setup needed:

* **Web request errors** — Rack middleware catches anything that bubbles past your controllers.
* **Background job failures** — `prepend perform_now` on `ActiveJob::Base` catches every failed job (Solid Queue, Sidekiq, async, inline — any adapter).
* **Rescued errors** — `Rails.error.subscribe` catches `rescue_from` blocks, ActionCable channel/connection errors, ActiveRecord async query errors, anything user code passes through `Rails.error.handle/.record`.
* **Manual capture** — `RbRunErrorReporter.capture(e, **context)` from anywhere in your code.
* **Script crashes** — `at_exit` catches uncaught raises in `bin/rails runner`, rake tasks, scheduled scripts.

```ruby
# Anywhere in your code:
begin
  risky_thing
rescue => e
  RbRunErrorReporter.capture(e, my_extra: "context")
  # decide whether to swallow or re-raise
end
```

---

## Optional: carry user/workspace context into jobs

The SDK's `PayloadBuilder` auto-attaches `Current.user` and
`Current.workspace` (and `Current.membership`) to every report. For
web requests these are typically already set by your auth layer.

For **background jobs**, add this to your `ApplicationJob` so a job
that takes a `User` or `Workspace` as one of its arguments
auto-populates `Current` for the duration of the perform:

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

Now failed jobs land in the collector's `error_reports` tagged with
the right `user_id` / `workspace_id`.

---

## Verifying it works

After deploying with the SDK configured:

```bash
bin/rails runner 'raise "smoke test from <your-app>"'
```

Then ask the operator to check the collector — your error should
appear in `error_reports` with `source_app` equal to the credential
name (e.g. `appA-prod RuntimeError: smoke test from appA`).

If you don't see it:

* Is `RbRunErrorReporter.configuration.enabled` true? (Default is
  `!Rails.env.test?` — make sure you're not running in test env.)
* Is the bearer token correct and not revoked? An invalid bearer
  produces `401` on the collector — ask the operator to grep their
  logs.
* Is the endpoint reachable from the client? An `HttpSink` network
  error logs a single line at warn level and drops the report; it
  never raises or blocks the request thread.

---

## Sinks

The SDK has three interchangeable sinks. Most client apps use
`HttpSink` (above). For reference:

| Sink           | Use it when                                                                              |
| -------------- | ---------------------------------------------------------------------------------------- |
| `HttpSink`     | Most clients. POSTs to a remote collector with bearer auth.                              |
| `DatabaseSink` | You ARE the collector (you've mounted the engine and want to skip the self-HTTP hop).    |
| `LogSink`      | Tests, dev, or "I just want JSON lines in `log/errors.log`".                             |

### HttpSink — async delivery, never blocks

Network I/O happens on a `BackgroundWorker` thread pool (defaults: 2
threads, 30-item bounded queue, `:discard` overflow policy). Your
request threads never wait on the collector.

Pass `threads: 0` to force synchronous delivery (useful in tests):

```ruby
RbRunErrorReporter::Sdk::Ruby::Sinks::HttpSink.new(
  endpoint: "...",
  token:    "...",
  worker:   RbRunErrorReporter::Sdk::Ruby::BackgroundWorker.new(threads: 0)
)
```

Other behavior:

* **Gzip** above 30 KB.
* **No retries** — a reporter that hangs is worse than one that drops a few. Transient errors are logged and dropped.
* **429 / Retry-After** — sets a backoff deadline; reports submitted while backed off are dropped instead of queued. Avoids stampeding the collector when it's already under pressure.
* **Never raises** — both `Reporter#capture` and the worker block are rescued. A misconfigured endpoint, expired DNS, or downed collector cannot crash your app.

---

## Capture-surface details

For when you need to understand exactly what's wrapped:

* **Rack middleware** — two middlewares inserted around `ActionDispatch::ShowExceptions` / `DebugExceptions`. Producer/consumer split (same technique as `sentry-rails`) so we catch exceptions both before AND after Rails' built-in rescuers convert them to error pages.
* **ActiveJob** — `prepend RbRunErrorReporter::Sdk::Ruby::ActiveJobExtension` on `ActiveJob::Base` via `ActiveSupport.on_load(:active_job)`. Must run before `:eager_load!`, which the engine does automatically.
* **Rails error reporter** — `Rails.error.subscribe(RailsErrorSubscriber.new)`. Skips noisy sources like `active_support.cache_store`.
* **at_exit** — registered at boot. Reads `$!` on exit; skips clean `SystemExit`s.

---

## Configuration reference

```ruby
RbRunErrorReporter.configure do |c|
  c.environment          # Rails env name — defaults to RAILS_ENV
  c.release              # Build / release identifier — defaults to ENV["GIT_SHA"] || ENV["HEROKU_SLUG_COMMIT"]
  c.enabled              # Master switch — defaults to true; rbrun overrides to !test
  c.sink                 # The sink instance — REQUIRED, no default
  c.pii_fields           # Substring denylist for PiiScrubber — defaults: password, token, secret, …
  c.ignored_exceptions   # Class-name list — defaults: RoutingError, RecordNotFound, InvalidAuthenticityToken
  c.ignored_paths        # Regex list — defaults: /assets/, /(health|up|ping)
  c.dedup_window_seconds # 0 = disabled; >0 = drop duplicate exceptions within window
  c.before_send          # ->(payload) { payload | nil }
  c.max_payload_bytes    # Collector hard cap — 1 MiB default
end
```

See [`configuration.rb`](./configuration.rb) for the full default
list with comments.
