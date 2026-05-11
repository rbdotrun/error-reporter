require "logger"
require "json"

module RbRunErrorReporter
  module Sdk
    module Ruby
      module Sinks
        # JSON-lines sink. Writes each payload as a single line to the
        # configured logger. Default in test env — assertions can grep
        # the captured log output without touching the DB.
        #
        # Production hosts that want a flat-file sink can target a
        # dedicated logger (e.g. `Logger.new("log/errors.log")`) and
        # ship via their existing log aggregator (Datadog, Loki, …).
        class LogSink
          PREFIX = "[RbRunErrorReporter]".freeze

          def initialize(logger: nil)
            @logger = logger || default_logger
          end

          def deliver(payload)
            @logger.error("#{PREFIX} #{payload.to_json}")
          end

          def flush
            @logger.respond_to?(:flush) ? @logger.flush : nil
          end

          private

            def default_logger
              if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
                Rails.logger
              else
                ::Logger.new($stdout)
              end
            end
        end
      end
    end
  end
end
