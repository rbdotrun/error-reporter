module RbRunErrorReporter
  # Retention job. Deletes `error_reports` rows older than the given
  # cutoff. Host wires this in `config/recurring.yml`:
  #
  #   delete_old_error_reports:
  #     class: "RbRunErrorReporter::DeleteOldErrorReportsJob"
  #     args:  [{ "older_than_days": 30 }]
  #     schedule: every day at 3am
  #
  # Idempotent — running twice in a row deletes nothing the second time.
  class DeleteOldErrorReportsJob < ApplicationJob
    DEFAULT_OLDER_THAN_DAYS = 30

    def perform(options = {})
      options = options.with_indifferent_access if options.respond_to?(:with_indifferent_access)
      days = (options[:older_than_days] || DEFAULT_OLDER_THAN_DAYS).to_i
      cutoff = days.days.ago
      deleted = ErrorReport.purge_older_than(cutoff)
      Rails.logger.info("[RbRunErrorReporter] purged #{deleted} error_reports older than #{cutoff.iso8601}")
      deleted
    end
  end
end
