Rails.application.routes.draw do
  # Mount point — clients POST to /error_reporter/errors.
  mount RbRunErrorReporter::Engine => "/error_reporter"

  # A tiny health check + status page at /, so `curl localhost:3000`
  # confirms the host is up before clients start reporting.
  get "/", to: ->(_env) {
    body = {
      status:           "ok",
      role:             "rbrun-error-reporter collector",
      collector_path:   "/error_reporter/errors",
      reports_count:    RbRunErrorReporter::ErrorReport.count,
      active_credentials: RbRunErrorReporter::IngestionCredential.active.count
    }.to_json
    [ 200, { "Content-Type" => "application/json" }, [ body ] ]
  }
end
