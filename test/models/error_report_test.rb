require "test_helper"

class RbRunErrorReporter::ErrorReportTest < ActiveSupport::TestCase
  setup { RbRunErrorReporter::ErrorReport.delete_all }

  def make_report(overrides = {})
    RbRunErrorReporter::ErrorReport.create!({
      fingerprint:     "fp1",
      exception_class: "RuntimeError",
      message:         "boom",
      environment:     "test",
      source:          "test",
      payload:         { schema_version: 1 },
      occurred_at:     Time.now.utc
    }.merge(overrides))
  end

  test "table_name is error_reports (not the namespaced default)" do
    assert_equal "error_reports", RbRunErrorReporter::ErrorReport.table_name
  end

  test "recent scope orders by occurred_at DESC" do
    older = make_report(occurred_at: 2.hours.ago)
    newer = make_report(occurred_at: 1.hour.ago)
    assert_equal [ newer, older ], RbRunErrorReporter::ErrorReport.recent.to_a
  end

  test "for_workspace filters by workspace_id" do
    ws_a = SecureRandom.uuid
    ws_b = SecureRandom.uuid
    a = make_report(workspace_id: ws_a)
    _b = make_report(workspace_id: ws_b)
    assert_equal [ a ], RbRunErrorReporter::ErrorReport.for_workspace(ws_a).to_a
  end

  test "purge_older_than deletes rows older than the cutoff" do
    keep = make_report(occurred_at: 1.day.ago)
    drop = make_report(occurred_at: 40.days.ago)
    deleted = RbRunErrorReporter::ErrorReport.purge_older_than(30.days.ago)
    assert_equal 1, deleted
    assert RbRunErrorReporter::ErrorReport.exists?(keep.id)
    refute RbRunErrorReporter::ErrorReport.exists?(drop.id)
  end

  test "grouped_counts groups by fingerprint" do
    make_report(fingerprint: "a")
    make_report(fingerprint: "a")
    make_report(fingerprint: "b")
    counts = RbRunErrorReporter::ErrorReport.grouped_counts
    assert_equal({ "a" => 2, "b" => 1 }, counts)
  end
end
