require "time"

module RbRunErrorReporter
  module Sdk
    module Ruby
      # Builds the schema-versioned payload hash from an exception +
      # ambient context. This is the only place where `Current` is read
      # — keeping that lookup centralized means the dependency on the
      # host app's `Current` constant is explicit and easy to swap.
      #
      # See WIRE_PROTOCOL.md for the field reference. The output of this
      # class is what HttpSink POSTs to the collector and what
      # DatabaseSink persists.
      class PayloadBuilder
        SCHEMA_VERSION = 1
        BACKTRACE_FRAME_LIMIT = 50

        def initialize(configuration)
          @configuration = configuration
        end

        def build(exception, env: nil, source: nil, **extra)
          {
            schema_version:  SCHEMA_VERSION,

            exception_class: exception.class.name,
            message:         exception.message.to_s,
            backtrace:       (exception.backtrace || []).first(BACKTRACE_FRAME_LIMIT),

            user_id:         current_user_id,
            workspace_id:    current_workspace_id,
            membership_id:   current_membership_id,

            source:,
            source_app:      nil,
            environment:     @configuration.environment,
            release:         @configuration.release,
            occurred_at:     Time.now.utc.iso8601(3),

            request:         env ? request_data(env) : nil,
            extra:
          }.compact
        end

        private

          # `defined?(::Current)` is the cheap gate; the rescue guards
          # against the rare case where Current is defined but the request
          # context hasn't been opened yet (raises ActiveSupport CurrentAttributes::Error).
          def current_user_id
            return nil unless defined?(::Current)

            ::Current.user&.id
          rescue StandardError
            nil
          end

          def current_workspace_id
            return nil unless defined?(::Current)

            ::Current.workspace&.id
          rescue StandardError
            nil
          end

          def current_membership_id
            return nil unless defined?(::Current)

            ::Current.membership&.id
          rescue StandardError
            nil
          end

          def request_data(env)
            req = ActionDispatch::Request.new(env)
            {
              method:     req.request_method,
              path:       req.path,
              full_path:  req.fullpath,
              request_id: req.request_id,
              ip:         req.remote_ip,
              user_agent: req.user_agent,
              referer:    req.referer,
              params:     req.filtered_parameters
            }
          rescue StandardError
            {}
          end
      end
    end
  end
end
