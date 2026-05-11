require "digest"

module RbRunErrorReporter
  module Sdk
    module Ruby
      module Sinks
        # Writes the payload to the collector's `error_reports` table via
        # the engine's `RbRunErrorReporter::ErrorReport` AR model.
        #
        # **Engine-only sink.** A Ruby host that does NOT mount the
        # engine (e.g. a pure-client app that reports over HTTP) should
        # not use this — there's no `ErrorReport` constant in that
        # process. We raise loudly if asked to deliver without the
        # model in scope, so the misconfiguration is visible at first
        # delivery rather than buried in a `NameError` somewhere.
        class DatabaseSink
          MissingModelError = Class.new(StandardError)

          # Default model is the engine's. Tests/specs can pass an
          # arbitrary AR class that responds to `.create!`.
          def initialize(model: nil)
            @model_name = model
          end

          def deliver(payload)
            model.create!(
              fingerprint:     fingerprint(payload),
              exception_class: payload[:exception_class],
              message:         payload[:message],
              environment:     payload[:environment],
              release:         payload[:release],
              source:          payload[:source],
              source_app:      payload[:source_app],
              user_id:         payload[:user_id],
              workspace_id:    payload[:workspace_id],
              payload:,
              occurred_at:     payload[:occurred_at]
            )
          end

          def flush
            # No-op — writes are synchronous to the DB.
          end

          private

            # Stable across runs: same exception class + same numeric-
            # neutralized message + same top-of-stack → same fingerprint.
            # The collector uses this for grouping ("this error happened
            # 4 871 times" UI later).
            def fingerprint(payload)
              normalized_message = payload[:message].to_s.gsub(/\d+/, "N")
              top_frames = Array(payload[:backtrace]).first(3).join("|")
              Digest::SHA1.hexdigest(
                [ payload[:exception_class], normalized_message, top_frames ].join("||")
              )
            end

            def model
              @model ||= resolve_model
            end

            def resolve_model
              if @model_name
                @model_name.is_a?(Class) ? @model_name : @model_name.to_s.constantize
              elsif defined?(RbRunErrorReporter::ErrorReport)
                RbRunErrorReporter::ErrorReport
              else
                raise MissingModelError, <<~MSG.squish
                DatabaseSink requires either an explicit `model:` argument
                or RbRunErrorReporter::ErrorReport to be defined (which
                happens automatically when the engine is mounted in the
                host app). For client-only apps that report over HTTP,
                use Sinks::HttpSink instead.
              MSG
              end
            end
        end
      end
    end
  end
end
