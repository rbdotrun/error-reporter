# Empty rackup file — never actually used to serve traffic. Its
# presence is what tells Rails' root-finding heuristic
# (`find_root_with_flag "config.ru"`) that `test/dummy/` IS the app
# root. Without this, Rails.root falls back to the gem repo root and
# every `config/...` path resolves to a non-existent location.
require_relative "config/environment"
run Rails.application
