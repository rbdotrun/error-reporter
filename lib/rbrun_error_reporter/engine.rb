require "rails/engine"

module RbRunErrorReporter
  # Mountable Rails engine. Owns:
  #
  #   * Rack middleware insertion (producer/consumer split, sentry-rails style)
  #   * ActiveJob hook (`prepend perform_now` on `ActiveJob::Base`)
  #   * Rails.error subscriber (covers `rescue_from`, ActionCable, AR async)
  #   * at_exit handler (covers `bin/rails runner`, rake tasks, scripts)
  #   * Auto-discovery of the engine's migrations (host runs `db:migrate`,
  #     no `rake railties:install:migrations` step required)
  #   * Routes for the collector controller — POST /errors with bearer auth.
  #     The host enables collection by mounting the engine:
  #
  #         mount RbRunErrorReporter::Engine, at: "/error_reporter"
  #
  #     Hosts that only want to *report* (and not collect) can skip the
  #     mount; the SDK pieces still work.
  class Engine < ::Rails::Engine
    isolate_namespace RbRunErrorReporter

    # ---- migrations -------------------------------------------------------
    #
    # Append the engine's `db/migrate` paths into the host's migration paths
    # so `bin/rails db:migrate` picks them up without a copy step.
    #
    # Skip when the host IS the engine itself (engine running its own
    # isolated tests). Comparison is explicit string equality — the
    # Rails Engines guide's canonical `app.root.to_s.match?(root.to_s)`
    # pattern uses `match?` as a REGEX match, which falsely matches any
    # host whose root is INSIDE the engine's directory tree (e.g.
    # `examples/host/` under `/gem`). That silently drops the engine's
    # migrations and the host crashes on first AR query against
    # `error_reports` or `ingestion_credentials`.
    initializer :append_migrations do |app|
      next if app.root.to_s == root.to_s

      config.paths["db/migrate"].expanded.each do |expanded_path|
        app.config.paths["db/migrate"] << expanded_path
      end
    end

    # ---- middleware (capture surface #1: unhandled web requests) ----------
    #
    # Two-layer producer/consumer split, mirroring sentry-rails:
    #
    #   * `RescuedExceptionInterceptor` sits next to `DebugExceptions` and
    #     stashes the raw exception in `env` BEFORE Rails' rescuers convert
    #     it into a 404/500 response. Without this, by the time the outer
    #     middleware sees the request, the exception has been swallowed and
    #     replaced with a rendered error page.
    #
    #   * `CaptureExceptions` sits outside `ShowExceptions`. It reads the
    #     stashed exception (rescued case) OR catches the raw exception
    #     (truly unhandled case, e.g. a middleware blew up upstream).
    initializer "rbrun_error_reporter.middleware" do |app|
      require "rbrun_error_reporter/sdk/ruby/rack/rescued_exception_interceptor"
      require "rbrun_error_reporter/sdk/ruby/rack/capture_exceptions"

      app.config.middleware.insert_after ActionDispatch::ShowExceptions,
                                         RbRunErrorReporter::Sdk::Ruby::Rack::CaptureExceptions
      app.config.middleware.insert_after ActionDispatch::DebugExceptions,
                                         RbRunErrorReporter::Sdk::Ruby::Rack::RescuedExceptionInterceptor
    end

    # ---- ActiveJob (capture surface #2: failed background jobs) -----------
    #
    # `prepend perform_now` on `ActiveJob::Base` so we wrap every job class
    # (Solid Queue, async, inline, anything). MUST run before `:eager_load!`
    # — once user job classes are loaded, prepending on the parent no longer
    # affects them.
    initializer "rbrun_error_reporter.active_job", before: :eager_load! do
      ActiveSupport.on_load(:active_job) do
        require "rbrun_error_reporter/sdk/ruby/active_job_extension"
        prepend RbRunErrorReporter::Sdk::Ruby::ActiveJobExtension
      end
    end

    # ---- Rails.error subscriber (capture surface #3) ---------------------
    #
    # Single hook covers:
    #   * controller `rescue_from` blocks (Rails wraps them)
    #   * ActionCable channel + connection errors
    #   * ActiveRecord async query errors
    #   * anything user code wraps with `Rails.error.handle / .record`
    config.after_initialize do |app|
      require "rbrun_error_reporter/sdk/ruby/rails_error_subscriber"
      app.executor.error_reporter.subscribe(RbRunErrorReporter::Sdk::Ruby::RailsErrorSubscriber.new)
    end

    # ---- at_exit (capture surface #5: runner / rake / script crashes) ----
    initializer "rbrun_error_reporter.at_exit" do
      at_exit do
        next unless RbRunErrorReporter.configuration.enabled

        exc = $!
        next if exc.nil?
        next if exc.is_a?(SystemExit) && exc.success?

        RbRunErrorReporter.capture(exc, source: "at_exit")
        RbRunErrorReporter.flush
      end
    end
  end
end
