# Dummy Rails app's Bundler bootstrap. Points BUNDLE_GEMFILE up at the
# gem's Gemfile so the dummy app inherits all the gem's test-time deps
# (combustion is unused; pg, webmock, minitest come from there) and the
# gem itself loads via `gemspec` in that Gemfile.
ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../../../Gemfile", __dir__)

require "bundler/setup"
