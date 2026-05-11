# Rails requires a secret_key_base. Hard-coded value is fine here —
# this app is test-only and never sees real traffic. Don't copy this
# into a real Rails app.
Dummy::Application.config.secret_key_base = "rbrun_error_reporter_dummy_secret_key_base_only_for_engine_tests"
