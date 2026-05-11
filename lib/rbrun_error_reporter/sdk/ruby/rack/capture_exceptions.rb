require "rbrun_error_reporter/sdk/ruby/rack/rescued_exception_interceptor"

module RbRunErrorReporter
  module Sdk
    module Ruby
      module Rack
        # The "consumer" half of the producer/consumer Rack middleware
        # split.
        #
        # Sits OUTSIDE `ActionDispatch::ShowExceptions`. Two paths:
        #
        #   1. Inner stack ran to completion (no raise propagated up
        #      here) but Rails converted an exception to a rendered
        #      error page. We read the exception out of `env` (stashed
        #      by RescuedExceptionInterceptor or by Rails itself).
        #
        #   2. An exception propagated all the way up (a middleware
        #      upstream of ShowExceptions raised, or ShowExceptions was
        #      disabled). We catch the raw exception, report, and
        #      re-raise — never swallow.
        class CaptureExceptions
          ENV_KEYS = [
            "rack.exception",
            "sinatra.error",
            "action_dispatch.exception",
            RescuedExceptionInterceptor::ENV_KEY
          ].freeze

          def initialize(app)
            @app = app
          end

          def call(env)
            response = @app.call(env)
            if (exc = exception_from_env(env))
              RbRunErrorReporter.capture(exc, env:, source: "rack", handled: true)
            end
            response
          rescue Exception => e # rubocop:disable Lint/RescueException
            RbRunErrorReporter.capture(e, env:, source: "rack", handled: false)
            raise
          end

          private

            def exception_from_env(env)
              ENV_KEYS.each do |key|
                exc = env[key]
                return exc if exc.is_a?(Exception)
              end
              nil
            end
        end
      end
    end
  end
end
