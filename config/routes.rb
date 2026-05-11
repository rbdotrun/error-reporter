RbRunErrorReporter::Engine.routes.draw do
  # Collector ingestion endpoint. See WIRE_PROTOCOL.md for the body
  # schema, auth headers, and response shape.
  post "errors", to: "errors#create"

  # Future admin surface mounts here. Intentionally empty for v1 — the
  # operator queries via Rails console (ErrorReport.recent).
end
