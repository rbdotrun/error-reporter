module RbRunErrorReporter
  module Sdk
    module Ruby
      # Subscriber for the Rails 7+ `Rails.error.handle / .record / .report`
      # surface. Registered via `app.executor.error_reporter.subscribe(...)`
      # in the engine.
      #
      # Covers, via one hook:
      #   * controller `rescue_from` blocks (Rails wraps them)
      #   * ActionCable channel + connection errors
      #   * ActiveRecord async query errors
      #   * any user-code call to `Rails.error.handle { ... }`
      #
      # Some `source` values are noisy and not useful to forward — most
      # notably ActiveSupport cache misses recorded by the framework
      # itself. Skip those.
      class RailsErrorSubscriber
        SKIP_SOURCES = /\A(active_support\.cache_store|activerecord\.connection_pool)\z/

        def report(error, handled:, severity:, context:, source: nil)
          return if source && SKIP_SOURCES.match?(source)

          RbRunErrorReporter.capture(
            error,
            source:        source || "rails.error",
            handled:,
            severity:,
            rails_context: context
          )
        end
      end
    end
  end
end
