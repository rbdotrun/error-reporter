# Build context is the gem repo root (set via docker-compose.yml). The
# whole gem is copied in so `bundle install` can resolve the
# `path: "../.."` Gemfile entry. The bind-mount in docker-compose.yml
# overlays the same path at runtime for live source edits.

FROM ruby:3.4-slim

ENV BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_JOBS=4 \
    LANG=C.UTF-8

RUN apt-get update -qq \
 && apt-get install --no-install-recommends -y \
      build-essential libpq-dev libyaml-dev curl postgresql-client \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /gem/examples/host

# Copy just the manifests first so `bundle install` is cached across
# source-only changes. Then copy the rest of the gem source so the
# `path: "../.."` resolution at gemspec eval time finds the lib/ tree.
COPY examples/host/Gemfile examples/host/Gemfile.lock* ./
COPY . /gem
RUN bundle install

EXPOSE 3000

ENTRYPOINT ["bin/docker-entrypoint"]
CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
