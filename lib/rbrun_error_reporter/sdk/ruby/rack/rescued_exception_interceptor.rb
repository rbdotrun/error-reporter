module RbRunErrorReporter
  module Sdk
    module Ruby
      module Rack
        # The "producer" half of the producer/consumer Rack middleware
        # split.
        #
        # Sits next to `ActionDispatch::DebugExceptions`. Re-raises after
        # stashing the raw exception in `env`, so the OUTER middleware
        # (`CaptureExceptions`) can read it. Without this, by the time
        # the outer middleware runs, Rails' rescuers have converted the
        # exception into a 4xx/5xx response and the raw exception is
        # gone.
        #
        # Insertion is done by the engine:
        #
        #   app.config.middleware.insert_after(
        #     ActionDispatch::DebugExceptions,
        #     RbRunErrorReporter::Sdk::Ruby::Rack::RescuedExceptionInterceptor
        #   )
        class RescuedExceptionInterceptor
          ENV_KEY = "rbrun_error_reporter.rescued_exception".freeze

          def initialize(app)
            @app = app
          end

          def call(env)
            @app.call(env)
          rescue Exception => e # rubocop:disable Lint/RescueException
            env[ENV_KEY] = e
            raise
          end
        end
      end
    end
  end
end
