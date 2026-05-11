FROM ruby:3.4-slim

ENV BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_JOBS=4 \
    LANG=C.UTF-8

RUN apt-get update -qq \
 && apt-get install --no-install-recommends -y \
      build-essential libyaml-dev curl \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /gem/examples/client

COPY examples/client/Gemfile examples/client/Gemfile.lock* ./
COPY . /gem
RUN bundle install

EXPOSE 4000

ENTRYPOINT ["bin/docker-entrypoint"]
CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "4000"]
