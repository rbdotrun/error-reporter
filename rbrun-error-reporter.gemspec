require_relative "lib/rbrun_error_reporter/version"

Gem::Specification.new do |spec|
  spec.name        = "rbrun-error-reporter"
  spec.version     = RbRunErrorReporter::VERSION
  spec.authors     = ["rbrun"]
  spec.summary     = "Error reporter SDK + mountable collector engine for Rails apps"
  spec.description = "Captures unhandled web/job/runner exceptions in a host Rails app and forwards them to a configurable sink (log, local DB, or HTTP to a central collector). Mountable engine ships a /errors POST endpoint with DB-backed per-source bearer auth so other apps can report into it. Wire protocol documented for cross-language SDKs."
  spec.license     = "Nonstandard"
  spec.homepage    = "https://github.com/rbdotrun/error-reporter"
  spec.metadata    = {
    "source_code_uri" => "https://github.com/rbdotrun/error-reporter",
    "bug_tracker_uri" => "https://github.com/rbdotrun/error-reporter/issues"
  }
  spec.required_ruby_version = ">= 3.4"

  spec.files = Dir[
    "lib/**/*.rb",
    "app/**/*.rb",
    "config/**/*.rb",
    "db/**/*.rb",
    "README*",
    "WIRE_PROTOCOL*"
  ]
  spec.require_paths = ["lib"]

  spec.add_dependency "rails", ">= 8.0"
  spec.add_dependency "concurrent-ruby", ">= 1.1"
end
