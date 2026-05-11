Rails.application.routes.draw do
  # Hit this and watch the SDK report the raise to the host.
  get  "/boom",  to: "boom#crash"

  # Status check.
  root to: ->(_env) {
    body = {
      status: "ok",
      role:   "rbrun-error-reporter example client",
      try:    "GET /boom — raises a RuntimeError, captured + POSTed to the host"
    }.to_json
    [ 200, { "Content-Type" => "application/json" }, [ body ] ]
  }
end
