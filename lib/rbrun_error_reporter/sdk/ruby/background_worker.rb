require "concurrent/executor/thread_pool_executor"
require "concurrent/executor/immediate_executor"

module RbRunErrorReporter
  module Sdk
    module Ruby
      # Async dispatch helper for sinks that perform network I/O
      # (HttpSink). Wraps a Concurrent::Ruby executor with a bounded
      # queue and a `:discard` overflow policy — under load we'd rather
      # drop reports than block the host's request threads.
      #
      # Pattern lifted from sentry-ruby's `Sentry::BackgroundWorker`.
      #
      #   * `threads: 0` → fall back to ImmediateExecutor (synchronous).
      #     Used in tests so assertions don't race the thread pool, and
      #     by hosts that want strictly inline delivery.
      #   * `threads: N (>0)` → ThreadPoolExecutor with `max_threads: N`,
      #     `max_queue: max_queue`, `fallback_policy: :discard`.
      #
      # The worker is interchangeable: HttpSink takes a `worker:` arg, so
      # a host can pass `BackgroundWorker.new(threads: 8, max_queue: 100)`,
      # or any object responding to `#submit { ... }` and `#shutdown`.
      class BackgroundWorker
        DEFAULT_THREADS = 2
        DEFAULT_MAX_QUEUE = 30
        DEFAULT_SHUTDOWN_TIMEOUT_SECONDS = 2

        attr_reader :threads, :max_queue

        def initialize(threads: DEFAULT_THREADS,
                       max_queue: DEFAULT_MAX_QUEUE,
                       shutdown_timeout: DEFAULT_SHUTDOWN_TIMEOUT_SECONDS,
                       logger: nil)
          @threads = threads
          @max_queue = max_queue
          @shutdown_timeout = shutdown_timeout
          @logger = logger
          @executor = build_executor
        end

        # Submit a block for execution. Returns true if accepted, false
        # if dropped (queue overflow on a ThreadPoolExecutor).
        def submit(&block)
          @executor.post do
            begin
              block.call
            rescue Exception => e # rubocop:disable Lint/RescueException
              # An error inside the worker MUST NOT propagate — we'd
              # crash the executor thread otherwise. Log and move on.
              log_error("worker block raised", e)
            end
          end
          true
        rescue Concurrent::RejectedExecutionError
          log_warn("worker queue full — dropped one report")
          false
        end

        # Block until pending work drains or `shutdown_timeout` elapses.
        # Safe to call multiple times.
        def shutdown
          return unless @executor.is_a?(Concurrent::ThreadPoolExecutor)

          @executor.shutdown
          @executor.wait_for_termination(@shutdown_timeout)
        end

        def synchronous?
          @threads.to_i <= 0
        end

        private

          def build_executor
            if synchronous?
              Concurrent::ImmediateExecutor.new
            else
              Concurrent::ThreadPoolExecutor.new(
                min_threads:      0,
                max_threads:      @threads,
                max_queue:        @max_queue,
                fallback_policy:  :discard
              )
            end
          end

          def log_warn(msg)
            (@logger || rails_logger)&.warn("[RbRunErrorReporter] #{msg}")
          end

          def log_error(msg, exc)
            (@logger || rails_logger)&.error(
              "[RbRunErrorReporter] #{msg}: #{exc.class}: #{exc.message}"
            )
          end

          def rails_logger
            defined?(Rails) && Rails.respond_to?(:logger) ? Rails.logger : nil
          end
      end
    end
  end
end
