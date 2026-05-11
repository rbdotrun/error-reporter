module RbRunErrorReporter
  module Sdk
    module Ruby
      # Walks the payload hash and replaces values whose keys match the
      # configured denylist with `[FILTERED]`. Case-insensitive substring
      # match, so `password`, `Password`, `user_password`, and
      # `PASSWORD_CONFIRMATION` are all caught by the `password` rule.
      #
      # Runs AFTER PayloadBuilder so any host-app-supplied extras flow
      # through scrubbing too. Note that Rails-filtered params
      # (`req.filtered_parameters`) are already redacted by Rails using
      # the host's `config.filter_parameters` list — this scrubber is
      # the second line of defense.
      class PiiScrubber
        REDACTED = "[FILTERED]".freeze

        def initialize(configuration)
          @denylist = configuration.pii_fields.map { |s| s.to_s.downcase }.freeze
        end

        def scrub(value)
          case value
          when Hash
            value.each_with_object({}) do |(k, v), out|
              out[k] = denied?(k) ? REDACTED : scrub(v)
            end
          when Array
            value.map { |v| scrub(v) }
          else
            value
          end
        end

        private

          def denied?(key)
            key_str = key.to_s.downcase
            @denylist.any? { |needle| key_str.include?(needle) }
          end
      end
    end
  end
end
