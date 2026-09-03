module LlamaBotRails
  # Reports unhandled Rails exceptions to the mothership, then re-raises so the
  # normal error page still renders. Pure observer — it changes no behavior.
  #
  # Position matters a lot here (see the engine initializer): this must sit
  # BELOW ActionDispatch::DebugExceptions in the stack. DebugExceptions renders
  # the error page without re-raising whenever show_exceptions is :all — which
  # is every Leo box, since they all run RAILS_ENV=development — so anything
  # inserted above it never sees an application exception at all.
  class ErrorTelemetryMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      @app.call(env)
    rescue Exception => exception # rubocop:disable Lint/RescueException
      # Belt and braces: the reporter already swallows everything internally,
      # but if it ever didn't, letting its exception escape here would replace
      # the app's real exception with a telemetry one — losing the actual bug
      # and lying to whoever renders the error page.
      begin
        LlamaBotRails::MothershipReporter.report_exception(
          exception, env: env, recovered: false, context: "rack_middleware"
        )
      rescue Exception # rubocop:disable Lint/RescueException
        nil
      end

      raise
    end
  end
end
