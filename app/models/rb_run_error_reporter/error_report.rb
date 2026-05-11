module RbRunErrorReporter
  # One captured error. Schema is deliberately app-agnostic — `user_id`
  # and `workspace_id` are opaque strings (no FK constraints) so the
  # same table can hold reports from any number of source apps, each
  # with their own identifier shape.
  #
  # Grouping happens via `fingerprint` (set by DatabaseSink based on
  # class + numeric-neutralized message + top-of-stack).
  class ErrorReport < ApplicationRecord
    # Zeitwerk would otherwise infer `rb_run_error_reporter_error_reports`
    # from the namespaced class. We share the table across the host app,
    # so use the bare name.
    self.table_name = "error_reports"

    scope :recent,         -> { order(occurred_at: :desc) }
    scope :for_user,       ->(id) { where(user_id: id.to_s) }
    scope :for_workspace,  ->(id) { where(workspace_id: id.to_s) }
    scope :for_source_app, ->(name) { where(source_app: name.to_s) }
    scope :by_fingerprint, ->(fp) { where(fingerprint: fp) }
    scope :since,          ->(time) { where("occurred_at >= ?", time) }

    # Convenience for the retention job — `delete_all` skips callbacks
    # which is fine here (no callbacks defined).
    def self.purge_older_than(time)
      where("occurred_at < ?", time).delete_all
    end

    # Grouped count for an eventual admin UI.
    def self.grouped_counts(scope = all)
      scope.group(:fingerprint).count
    end
  end
end
