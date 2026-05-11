require "concurrent/map"
require "digest"

module RbRunErrorReporter
  module Sdk
    module Ruby
      # In-process dedup window. Off by default
      # (`configuration.dedup_window_seconds = 0`). Useful when a tight
      # loop raises the same error 10 000 times per second and you'd
      # rather see it once a minute than fill the collector with noise.
      #
      # This is per-process. Cross-process dedup happens at the
      # collector via the `fingerprint` column (a unique-fingerprint
      # query/groups in the DB).
      module Dedup
        SEEN = Concurrent::Map.new
        MAX_TRACKED = 1000

        class << self
          def duplicate?(exception, window:)
            return false if window.to_i <= 0

            key = fingerprint(exception)
            now = monotonic_now
            last = SEEN[key]

            if last && (now - last) < window
              true
            else
              SEEN[key] = now
              prune(now, window) if SEEN.size > MAX_TRACKED
              false
            end
          end

          def reset!
            SEEN.clear
          end

          private

            def fingerprint(exception)
              Digest::SHA1.hexdigest(
                "#{exception.class.name}|#{exception.message}|#{exception.backtrace&.first}"
              )
            end

            def monotonic_now
              Process.clock_gettime(Process::CLOCK_MONOTONIC)
            end

            def prune(now, window)
              SEEN.each_pair do |k, t|
                SEEN.delete(k) if (now - t) > window
              end
            end
        end
      end
    end
  end
end
