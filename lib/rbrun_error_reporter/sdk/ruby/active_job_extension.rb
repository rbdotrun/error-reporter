module RbRunErrorReporter
  module Sdk
    module Ruby
      # `prepend`ed onto `ActiveJob::Base` by the engine. Wraps every
      # job's `perform_now`. Catches both `StandardError` and
      # non-StandardError exceptions (LoadError, SystemCallError, etc.)
      # — Rails' built-in `retry_on / discard_on` machinery only sees
      # the re-raise after we've captured.
      #
      # Inclusion path:
      #
      #   ActiveSupport.on_load(:active_job) do
      #     prepend RbRunErrorReporter::Sdk::Ruby::ActiveJobExtension
      #   end
      #
      # MUST run before `:eager_load!` so the prepend lands in the
      # ancestor chain before user job classes are loaded — otherwise
      # the chain points at the un-prepended `ActiveJob::Base` and the
      # wrap is invisible.
      module ActiveJobExtension
        def perform_now
          super
        rescue Exception => e # rubocop:disable Lint/RescueException
          RbRunErrorReporter.capture(
            e,
            source: "active_job",
            job: {
              class:      self.class.name,
              job_id:,
              queue:      queue_name,
              arguments:  arguments_for_payload,
              executions:
            }
          )
          raise
        end

        private

          # Don't serialize the world. Cap to scalar/GlobalID. PiiScrubber
          # will redact known-sensitive keys; this layer just keeps the
          # payload from carrying an entire object graph.
          def arguments_for_payload
            arguments.map do |arg|
              if arg.is_a?(ActiveRecord::Base)
                arg.to_global_id.to_s
              else
                arg
              end
            end
          rescue StandardError
            [ "[unserializable]" ]
          end
      end
    end
  end
end
