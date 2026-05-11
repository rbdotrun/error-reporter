require "rbrun_error_reporter/version"

# Ruby SDK — capture surface + funnel + sinks. Sibling SDKs in other
# languages would live under `lib/rbrun_error_reporter/sdk/<lang>/` (or
# more realistically in their own packages); the HTTP wire format
# (WIRE_PROTOCOL.md) is the cross-language contract.
require "rbrun_error_reporter/sdk/ruby/configuration"
require "rbrun_error_reporter/sdk/ruby/payload_builder"
require "rbrun_error_reporter/sdk/ruby/pii_scrubber"
require "rbrun_error_reporter/sdk/ruby/dedup"
require "rbrun_error_reporter/sdk/ruby/background_worker"
require "rbrun_error_reporter/sdk/ruby/reporter"
require "rbrun_error_reporter/sdk/ruby/sinks/log_sink"
require "rbrun_error_reporter/sdk/ruby/sinks/database_sink"
require "rbrun_error_reporter/sdk/ruby/sinks/http_sink"

# Engine (collector side) — only loaded when running inside a Rails app.
require "rbrun_error_reporter/engine" if defined?(Rails)

# Public API surface.
#
# Three things any host app touches:
#
#   1. `RbRunErrorReporter.configure { |c| c.sink = ... }` (initializer)
#   2. `RbRunErrorReporter.capture(exception, **context)` (manual report)
#   3. Collector hosts only:
#        `mount RbRunErrorReporter::Engine, at: "/error_reporter"`
#
# Everything else (Rack middleware, ActiveJob hook, Rails.error
# subscriber, at_exit) is wired automatically by the engine.
#
# Constants:
#   * `RbRunErrorReporter::*` — the SHIPPED public surface (this module,
#     `Engine`, AR models, controllers, jobs).
#   * `RbRunErrorReporter::Sdk::Ruby::*` — internal implementation of the
#     Ruby SDK. Stable as a private API; host apps shouldn't depend on it.
module RbRunErrorReporter
  class << self
    def configure
      yield(configuration)
    end

    def configuration
      @configuration ||= Sdk::Ruby::Configuration.new
    end

    # Test/dev only — never call from app code. Resets process-wide state.
    def reset_configuration!
      @configuration = Sdk::Ruby::Configuration.new
      Sdk::Ruby::Dedup.reset!
    end

    # The single funnel. Every capture path lands here. Filtering,
    # scrubbing, context attachment, and sink dispatch happen below.
    #
    # Returns the delivered payload hash (for tests), or nil if the
    # report was dropped (disabled / ignored / deduped / before_send
    # returned nil / internal error).
    def capture(exception, **context)
      Sdk::Ruby::Reporter.new(configuration).capture(exception, **context)
    end

    # Flush any pending async deliveries (HttpSink's background worker).
    # The engine's at_exit hook calls this; app code generally doesn't
    # need to.
    def flush
      sink = configuration.sink
      sink.respond_to?(:flush) ? sink.flush : nil
    rescue StandardError
      nil
    end
  end
end
