module RbRunErrorReporter
  module Sdk
    module Ruby
      # Process-wide configuration for the Ruby SDK. Mutated by the host
      # app via `RbRunErrorReporter.configure { |c| ... }` in an
      # initializer.
      #
      # Default values are tuned so the gem is safe to require with no
      # configuration at all — `enabled` defaults to true but `sink` is
      # nil, which means `Reporter#capture` will short-circuit at the
      # sink-dispatch step. The engine's initializer in the host wires
      # the actual sink.
      class Configuration
        attr_accessor :sink,
                      :environment,
                      :release,
                      :enabled,
                      :pii_fields,
                      :ignored_exceptions,
                      :ignored_paths,
                      :dedup_window_seconds,
                      :before_send,
                      :max_payload_bytes,
                      :ingestion_tokens

        DEFAULT_PII_FIELDS = %w[
          password password_confirmation token secret api_key
          credit_card ssn authorization cookie set-cookie
        ].freeze

        DEFAULT_IGNORED_EXCEPTIONS = %w[
          ActionController::RoutingError
          ActiveRecord::RecordNotFound
          ActionController::InvalidAuthenticityToken
        ].freeze

        DEFAULT_IGNORED_PATHS = [
          %r{\A/assets/},
          %r{\A/(health|up|ping)\z}
        ].freeze

        # 1 MiB. Collector rejects payloads larger than this (returns 413).
        DEFAULT_MAX_PAYLOAD_BYTES = 1 * 1024 * 1024

        def initialize
          @enabled              = true
          @environment          = ENV.fetch("RAILS_ENV", "development")
          @release              = ENV["GIT_SHA"] || ENV["HEROKU_SLUG_COMMIT"]
          @sink                 = nil
          @pii_fields           = DEFAULT_PII_FIELDS.dup
          @ignored_exceptions   = DEFAULT_IGNORED_EXCEPTIONS.dup
          @ignored_paths        = DEFAULT_IGNORED_PATHS.dup
          @dedup_window_seconds = 0
          @before_send          = nil
          @max_payload_bytes    = DEFAULT_MAX_PAYLOAD_BYTES
          @ingestion_tokens     = []
        end

        # Returns true if the given exception (and optional request path)
        # should be filtered out before the sink ever sees it.
        def ignore?(exception, path: nil)
          return true if path && ignored_paths.any? { |pat| path =~ pat }

          klass = exception.class
          ignored_exceptions.any? do |name|
            # Match by exact class name OR by ancestor chain — so
            # configuring "MyApp::HandledError" catches subclasses too.
            klass.name == name || klass.ancestors.any? { |a| a.name == name }
          end
        end
      end
    end
  end
end
