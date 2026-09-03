module LlamaBotRails
  # Bridges Rails' own error reporter into mothership telemetry, so errors that
  # never travel through the Rack stack still surface on the fleet dashboard —
  # background jobs, ActiveRecord async queries, and anything the app reports
  # via Rails.error.handle / Rails.error.record.
  #
  # Overlap with ErrorTelemetryMiddleware is expected and harmless:
  # MothershipReporter marks the exception object itself, so whichever path
  # sees it first wins and the other no-ops.
  class ErrorSubscriber
    # Rails.error.report severity is :error, :warning or :info. :info is
    # bookkeeping, not breakage, and reporting it would burn throttle budget
    # that a real 500 needs.
    REPORTED_SEVERITIES = %i[error warning].freeze

    def report(error, handled:, severity:, context: {}, source: nil)
      return unless REPORTED_SEVERITIES.include?(severity)

      LlamaBotRails::MothershipReporter.report_exception(
        error,
        env: rack_env_from(context),
        recovered: !!handled,
        context: [ "rails_error_reporter", source.presence ].compact.join(":")
      )
      nil
    rescue Exception # rubocop:disable Lint/RescueException
      # An error reporter that raises would turn a handled error into a crash.
      nil
    end

    private

    # Recover the request from Rails' execution context.
    #
    # This is NOT a nicety — without it every real HTTP 500 loses its method and
    # path. ActionDispatch::Executor (and its subclass Reloader) rescues, reports
    # to Rails.error, and only THEN re-raises; on a Leo box the Reloader sits
    # INSIDE both ErrorTelemetryMiddleware and the Leonardo error page. So this
    # subscriber always wins the race to report a crashing request, and whatever
    # context it fails to attach is simply gone: the reporter marks the exception
    # once reported, and the server's dedup only bumps a counter — it never
    # upgrades an already-stored traceback.
    #
    # Rails merges ActiveSupport::ExecutionContext into the reported context, and
    # ActionController::Instrumentation puts the live controller on it for the
    # duration of a request.
    def rack_env_from(context)
      return nil unless context.respond_to?(:[])

      request = context[:request]
      request = context[:controller].request if request.nil? && context[:controller].respond_to?(:request)
      request.env if request.respond_to?(:env)
    rescue StandardError
      nil
    end
  end
end
