# Mirrors the recommended host-app pattern (see the gem's Ruby SDK
# README). Extracts user/workspace/membership from job arguments into
# Current so failed jobs auto-attach the right context.
#
# Lives here so the engine's ActiveJob integration test can exercise
# the same flow real host apps will.
class ApplicationJob < ActiveJob::Base
  before_perform do |job|
    job.arguments.each do |arg|
      case arg
      when ::User       then ::Current.user       = arg
      when ::Workspace  then ::Current.workspace  = arg
      when ::Membership then ::Current.membership = arg
      end
    end
  end
end
