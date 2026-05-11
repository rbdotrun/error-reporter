# rbrun-error-reporter — HTTP wire protocol

The wire format between a **reporter** (any-language client SDK) and a
**collector** (a host that has mounted `RbRunErrorReporter::Engine`).

This document is the source of truth for SDK implementers. If you are
writing a new SDK (Python / JS / Go / Elixir / Swift / Rust / …) target
**this contract**, not the Ruby SDK's internals.

The Ruby SDK shipped with this gem implements this protocol via
`RbRunErrorReporter::Sinks::HttpSink`.

---

## Endpoint

```
POST <engine_mount>/errors
```

A host mounts the engine wherever it likes:

```ruby
# Host's config/routes.rb
mount RbRunErrorReporter::Engine, at: "/error_reporter"
```

So the collector URL becomes e.g. `https://my-host.example/error_reporter/errors`.

The full endpoint URL is given to the SDK by the operator who issued
the credential — the SDK does not derive or assume the path.

---

## Auth

```
Authorization: Bearer <token>
```

Tokens are issued by the collector operator (rbrun side) via:

```ruby
RbRunErrorReporter::IngestionCredential.issue!(name: "appA-prod")
# => { credential: <record>, token: "<raw_token_returned_once>" }
```

The raw token is returned **once** at issue time. The collector stores
only a SHA256 digest of the token; comparison is constant-time.

A credential has:

  * `name` — operator-chosen label (used as `source_app` if the body
    omits it).
  * `revoked_at` — null = active, datetime = revoked (any token presenting
    a revoked credential digest is rejected).
  * `last_used_at` — updated on successful auth (rate-limited to one
    write per minute per credential to avoid write amplification).

---

## Request

### Headers

| Header             | Required | Value                                       |
| ------------------ | -------- | ------------------------------------------- |
| `Authorization`    | yes      | `Bearer <token>`                            |
| `Content-Type`     | yes      | `application/json`                          |
| `Content-Encoding` | no       | `gzip` if the body is gzipped (recommended > 30 KB) |
| `User-Agent`       | no       | recommended: `<sdk-name>/<version>`         |

### Body — JSON

```json
{
  "schema_version": 1,
  "exception_class": "RuntimeError",
  "message": "wrong number of arguments (given 1, expected 0)",
  "backtrace": [
    "/app/lib/foo.rb:42:in `bar'",
    "/app/lib/baz.rb:17:in `qux'"
  ],
  "occurred_at": "2026-05-11T12:34:56.789Z",
  "environment": "production",
  "release": "abc1234",
  "source": "rack",
  "source_app": "appA-prod",
  "user_id": "uuid-or-string-or-null",
  "workspace_id": "uuid-or-string-or-null",
  "request": {
    "method": "POST",
    "path": "/foo/bar",
    "full_path": "/foo/bar?id=1",
    "request_id": "req_…",
    "ip": "203.0.113.7",
    "user_agent": "Mozilla/5.0 …",
    "referer": "https://example.com/",
    "params": { "id": "1", "password": "[FILTERED]" }
  },
  "extra": {
    "job": { "class": "MyJob", "job_id": "…", "queue": "default" }
  }
}
```

### Field reference

| Field             | Type                         | Required | Notes                                                                              |
| ----------------- | ---------------------------- | -------- | ---------------------------------------------------------------------------------- |
| `schema_version`  | integer                      | yes      | Currently `1`. Older/newer versions → 400.                                         |
| `exception_class` | string                       | yes      | Fully qualified class name in the source language.                                 |
| `message`         | string                       | yes      | Exception message. PII should already be scrubbed by the SDK before sending.       |
| `backtrace`       | array of strings             | no       | Stack frames, deepest first. SDKs should cap at ~50 frames.                        |
| `occurred_at`     | string (ISO 8601 UTC)        | yes      | When the exception was raised, in the reporter's clock.                            |
| `environment`     | string                       | yes      | `production` / `staging` / `development` / etc.                                    |
| `release`         | string                       | no       | Git SHA, semver, build id — whatever the SDK was configured with.                  |
| `source`          | string (enum)                | yes      | `rack` / `active_job` / `rails.error` / `at_exit` / `manual` / language-equivalents. |
| `source_app`      | string                       | no       | Identifies the originating service. Defaults to the credential's `name` if omitted. |
| `user_id`         | string                       | no       | Opaque identifier from the reporter's user system. The collector does not enforce a foreign key. |
| `workspace_id`    | string                       | no       | Same: opaque tenant identifier from the reporter.                                  |
| `request`         | object                       | no       | Present for web-request errors. Keys above are typical; collector preserves the whole object. |
| `extra`           | object                       | no       | Catch-all for source-specific context (job metadata, span ids, …).                 |

SDKs **must** scrub sensitive fields (passwords, tokens, cookies, …)
from `message`, `request.params`, and `extra` **before** sending. The
collector does not re-scrub.

---

## Responses

### 202 Accepted — stored

```json
{
  "status": "accepted",
  "id": "<error_report_uuid>"
}
```

### 400 Bad Request — malformed / unsupported version

```json
{
  "status": "error",
  "reason": "schema_version_unsupported" | "malformed_json" | "missing_field:<field>"
}
```

### 401 Unauthorized — missing, malformed, revoked, or unknown bearer

```json
{ "status": "error", "reason": "unauthorized" }
```

### 413 Payload Too Large

```json
{ "status": "error", "reason": "payload_too_large" }
```

Hard cap currently 1 MiB (configurable on the collector side via
`RbRunErrorReporter.configuration.max_payload_bytes`).

### 429 Too Many Requests

```json
{ "status": "error", "reason": "rate_limited" }
```

Headers: `Retry-After: <seconds>`. SDKs should respect this for the
indicated duration and drop incoming events (do **not** retry — back off).

---

## Versioning

The on-the-wire `schema_version` integer is bumped on incompatible
changes (renamed/removed fields, changed types). Additive changes
(new optional fields) do **not** bump the version; SDKs ignore unknown
fields gracefully.

The collector accepts the current version and (whenever possible) the
previous one during a rollout window.

---

## SDK responsibilities (any language)

A compliant SDK:

  1. Captures unhandled exceptions from the platform's natural seams
     (HTTP request lifecycle, background job framework, scheduler,
     process exit).
  2. Builds a payload matching the schema above.
  3. Scrubs PII before sending (configurable denylist).
  4. POSTs over HTTPS with `Authorization: Bearer`.
  5. Does **not** retry on failure — log + drop. Optionally honors
     `Retry-After` on 429.
  6. Sends asynchronously when possible (bounded queue, discard on
     overflow). Network latency must not block the host app.
  7. Never raises out of its capture path. The reporter is the safety
     net; it must not become the bug.
