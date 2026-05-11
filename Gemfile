source "https://rubygems.org"

# Load this gem's runtime + development dependencies from the gemspec.
gemspec

group :development, :test do
  gem "rubocop-rails-omakase", require: false
end

group :test do
  # Postgres in tests — engine migrations use jsonb + uuid types,
  # which means SQLite is not a viable target.
  gem "pg", "~> 1.5"

  # HTTP mocking for HttpSink tests.
  gem "webmock", "~> 3.20"

  gem "minitest", "~> 5.20"
end
