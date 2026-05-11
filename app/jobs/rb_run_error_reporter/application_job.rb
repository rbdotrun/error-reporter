module RbRunErrorReporter
  # Engine-local job base. Inherits from the host's ApplicationJob so
  # any host-level retry/discard rules apply to engine jobs too.
  class ApplicationJob < ::ApplicationJob
  end
end
