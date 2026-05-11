# Bundler will `require "rbrun-error-reporter"` by default for a gem with
# this name. Forward to the canonical underscored entry point so all the
# code can live under lib/rbrun_error_reporter/ (which matches the
# `RbRunErrorReporter` constant Zeitwerk expects).
require "rbrun_error_reporter"
