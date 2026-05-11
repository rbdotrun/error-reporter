module RbRunErrorReporter
  # Engine-local base controller. Inherits from `ActionController::API`
  # because the collector is a pure-JSON ingest endpoint — no flash, no
  # cookies, no view layer. CSRF protection from the host's
  # `ApplicationController` would also fight bearer-auth POSTs from
  # other origins.
  class ApplicationController < ActionController::API
  end
end
