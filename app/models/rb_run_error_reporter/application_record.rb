module RbRunErrorReporter
  # Engine-local abstract base. Inherits from the host app's
  # ::ApplicationRecord so we share its primary connection
  # (rbrun's multi-DB setup connects ApplicationRecord to :primary,
  # and we want error_reports + ingestion_credentials on :primary too).
  #
  # `abstract_class = true` keeps STI rules from looking for a table
  # called `rb_run_error_reporter_application_records`.
  class ApplicationRecord < ::ApplicationRecord
    self.abstract_class = true
  end
end
