require "test_helper"

# Engine integration: failing jobs land in error_reports, and the
# dummy app's ApplicationJob `before_perform` (the recommended pattern
# we tell host apps to copy) extracts User/Workspace from job
# arguments into Current. Full chain — Reporter → DatabaseSink →
# error_reports row with the right user_id / workspace_id.
class IntegrationActiveJobTest < ActiveJob::TestCase
  class JobThatRaises < ActiveJob::Base
    def perform; raise "job_boom"; end
  end

  # Inherits from the dummy app's ApplicationJob, which carries the
  # before_perform Current-extraction (the documented host-app
  # pattern). That's the seam under test.
  class JobThatExtractsCurrent < ApplicationJob
    cattr_accessor :captured_user_id
    cattr_accessor :captured_workspace_id

    def perform(user, workspace)
      self.class.captured_user_id      = Current.user&.id
      self.class.captured_workspace_id = Current.workspace&.id
      raise "needs_context"
    end
  end

  setup do
    @old_sink = RbRunErrorReporter.configuration.sink
    RbRunErrorReporter.configuration.sink = RbRunErrorReporter::Sdk::Ruby::Sinks::DatabaseSink.new
    RbRunErrorReporter::ErrorReport.delete_all
    JobThatExtractsCurrent.captured_user_id      = nil
    JobThatExtractsCurrent.captured_workspace_id = nil
  end

  teardown do
    RbRunErrorReporter.configuration.sink = @old_sink
  end

  test "the ActiveJob extension is prepended to ActiveJob::Base" do
    assert_includes ActiveJob::Base.ancestors,
                    RbRunErrorReporter::Sdk::Ruby::ActiveJobExtension
  end

  test "a failing job lands in error_reports with source = active_job" do
    assert_raises(RuntimeError) { JobThatRaises.perform_now }
    report = RbRunErrorReporter::ErrorReport.last
    refute_nil report
    assert_equal "active_job",   report.source
    assert_equal "RuntimeError", report.exception_class
  end

  test "ApplicationJob.before_perform extracts Current.user/Current.workspace from arguments" do
    alice = User.create!(email:      "alice@example.com", name: "Alice")
    acme  = Workspace.create!(slug:  "acme",              name: "Acme")

    assert_raises(RuntimeError) { JobThatExtractsCurrent.perform_now(alice, acme) }

    # before_perform fired: Current was set by the time perform ran.
    assert_equal alice.id, JobThatExtractsCurrent.captured_user_id
    assert_equal acme.id,  JobThatExtractsCurrent.captured_workspace_id

    # And the persisted report carries the right IDs.
    report = RbRunErrorReporter::ErrorReport.last
    assert_equal alice.id, report.user_id
    assert_equal acme.id,  report.workspace_id
  end
end
