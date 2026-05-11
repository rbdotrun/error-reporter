Rails.application.routes.draw do
  # Mount the engine the same way a real host would.
  mount RbRunErrorReporter::Engine => "/error_reporter"
end
