require "test_helper"

class RbRunErrorReporter::DeleteOldErrorReportsJobTest < ActiveJob::TestCase
  setup { RbRunErrorReporter::ErrorReport.delete_all }

  def make(overrides = {})
    RbRunErrorReporter::ErrorReport.create!({
      fingerprint: "fp", exception_class: "RuntimeError", message: "x",
      environment: "test", source: "test", payload: { schema_version: 1 },
      occurred_at: Time.now.utc
    }.merge(overrides))
  end

  test "deletes rows older than the configured window" do
    keep = make(occurred_at: 1.day.ago)
    drop = make(occurred_at: 40.days.ago)

    deleted = RbRunErrorReporter::DeleteOldErrorReportsJob.perform_now(older_than_days: 30)

    assert_equal 1, deleted
    assert RbRunErrorReporter::ErrorReport.exists?(keep.id)
    refute RbRunErrorReporter::ErrorReport.exists?(drop.id)
  end

  test "default window is 30 days" do
    make(occurred_at: 31.days.ago)
    deleted = RbRunErrorReporter::DeleteOldErrorReportsJob.perform_now
    assert_equal 1, deleted
  end

  test "is idempotent — running twice deletes nothing the second time" do
    make(occurred_at: 60.days.ago)
    assert_equal 1, RbRunErrorReporter::DeleteOldErrorReportsJob.perform_now
    assert_equal 0, RbRunErrorReporter::DeleteOldErrorReportsJob.perform_now
  end
end
