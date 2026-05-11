# examples/ — end-to-end demo

Two minimal Rails apps + docker-compose so you can watch the full
host ↔ client flow on your laptop in one command.

```
┌────────────────────────────────────┐         ┌────────────────────────────────────┐
│ examples/client/                   │         │ examples/host/                     │
│ ─ "any Rails app on the internet"  │         │ ─ "the operator host (rbrun)"      │
│                                    │         │                                    │
│  GET /boom  ─→  raises             │ HTTPS   │  POST /error_reporter/errors       │
│                                    │ ──────→ │   ↓ IngestionCredential lookup     │
│  Rack middleware catches the raise │         │   ↓ DatabaseSink                   │
│   ↓ RbRunErrorReporter.capture(e)  │         │   ↓                                │
│   ↓ HttpSink (Net::HTTP, bearer)   │         │  error_reports table               │
└────────────────────────────────────┘         └────────────────────────────────────┘
                                                            ↑
                                                        PostgreSQL
```

## Quick start

Requires `dip` (https://github.com/bibendi/dip). One-time setup:

```bash
cd examples
cp .env.example .env       # has a pre-shared token; fine for the demo
dip up
```

That single `dip up` boots three containers: `db` (Postgres), `host`
(collector, port 3000), and `client` (reporter, port 4000). The
host's entrypoint runs `db:prepare && db:seed`, which idempotently
provisions an `IngestionCredential` whose plaintext matches
`$ERROR_REPORTER_TOKEN`. The client's `HttpSink` reads the same env
var. No manual credential dance.

## See the flow

```bash
# Trigger a captured exception
dip boom
# → client returned 500

# See it on the host
dip show-reports
# → [example-client] RuntimeError: boom from example client at 2026-…
```

Or open in a browser:

* http://localhost:4010/      — client status
* http://localhost:4010/boom  — raises, reports to host
* http://localhost:3010/      — host status + count of captured reports

## Working inside the containers

| Command            | What                                                |
| ------------------ | --------------------------------------------------- |
| `dip up`           | Boot everything                                     |
| `dip down`         | Stop and remove containers                          |
| `dip logs`         | Tail all logs                                       |
| `dip host`         | Bash in the host container                          |
| `dip host-console` | Rails console on the host                           |
| `dip host-rails`   | Arbitrary Rails command on the host                 |
| `dip client`       | Bash in the client container                        |
| `dip client-console` | Rails console on the client                       |
| `dip boom`         | curl the client's /boom (triggers a captured raise) |
| `dip show-reports` | Print recent rows from the host's error_reports     |

## What this demos vs. real use

The demo's "operator" is just a minimal Rails app that mounts the
engine. Real operators (rbrun) wire the engine into their existing
app — no separate host process.

The demo pre-shares the bearer token via `.env`. Real operators issue
tokens with `RbRunErrorReporter::IngestionCredential.issue!`, capture
the returned plaintext **once**, and deliver it to the client team out
of band (1Password, signed message, secret manager). The seed file at
`host/db/seeds.rb` cheats by digesting an env var so the demo boots
without manual steps; **don't copy this pattern into production**.

## File layout

```
examples/
├── README.md
├── docker-compose.yml
├── dip.yml
├── .env.example
├── host/
│   ├── Dockerfile
│   ├── Gemfile             ← `gem "rbrun-error-reporter", path: "../.."`
│   ├── config/             ← minimal Rails config
│   │   ├── routes.rb       ← `mount RbRunErrorReporter::Engine => "/error_reporter"`
│   │   └── initializers/error_reporter.rb   ← DatabaseSink
│   ├── db/seeds.rb         ← idempotent credential from $ERROR_REPORTER_TOKEN
│   └── bin/{rails,docker-entrypoint}
└── client/
    ├── Dockerfile
    ├── Gemfile             ← same path: "../.."
    ├── app/controllers/boom_controller.rb   ← the raising endpoint
    ├── config/
    │   ├── routes.rb       ← `get "/boom" => "boom#crash"`
    │   └── initializers/error_reporter.rb   ← HttpSink → http://host:3000/...
    └── bin/{rails,docker-entrypoint}
```

Both apps depend on the gem via `path: "../.."`, so editing the gem
source while the stack is running picks up next time a container
reboots (`dip restart host` or `dip restart client`). No image
rebuild needed.
