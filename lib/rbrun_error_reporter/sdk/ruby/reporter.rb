module RbRunErrorReporter
  module Sdk
    module Ruby
      # The single funnel through which every capture path flows.
      # Filter → Dedup → Build → Scrub → before_send → Sink.
      #
      # **The reporter MUST NOT raise.** It's the safety net; if it
      # becomes the source of new errors, capture-during-capture loops
      # the host out of existence. The outer rescue logs and swallows.
      class Reporter
        def initialize(configuration)
          @configuration = configuration
        end

        def capture(exception, **context)
          return nil unless @configuration.enabled
          return nil if exception.nil?
          return nil if @configuration.ignore?(exception, path: context[:path])
          return nil if Dedup.duplicate?(exception, window: @configuration.dedup_window_seconds)
          return nil if @configuration.sink.nil?

          payload = PayloadBuilder.new(@configuration).build(exception, **context)
          payload = PiiScrubber.new(@configuration).scrub(payload)

          if (callback = @configuration.before_send)
            payload = callback.call(payload)
            return nil if payload.nil?
          end

          @configuration.sink.deliver(payload)
          payload
        rescue StandardError => e
          # Last line of defense. Log if we have a logger, otherwise
          # silently drop — never re-raise. A reporter that crashes the
          # request it was protecting is worse than one that drops a
          # report.
          log_internal_failure(e)
          nil
        end

        private

          def log_internal_failure(exception)
            return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

            Rails.logger.error(
              "[RbRunErrorReporter] internal failure: #{exception.class}: #{exception.message}"
            )
          end
      end
    end
  end
end
