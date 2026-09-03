require "net/http"
require "uri"
require "json"
require "time"
require "llama_bot_rails/error_log"

module LlamaBotRails
  # Fire-and-forget Rails-side error telemetry to the LlamaPress mothership.
  #
  # Until this existed, only the Python side of a Leo box reported errors
  # (LlamaBot app/services/mothership_client.py#report_error). A customer-facing
  # Rails crash — a pending migration after a bad update, a CSRF failure, a 500
  # from agent-written code — was invisible to the fleet dashboards unless a
  # human SSHed in. This class is the Rails half; the mothership receiver needed
  # no changes (it already allowlists source "rails_app").
  #
  # Semantics mirror the Python client deliberately: 5s timeouts, every
  # exception swallowed, no retry. A telemetry bug must NEVER break or slow a
  # customer request, so the public entrypoint catches Exception (not
  # StandardError) and the delivery runs off the request thread.
  #
  # == The fingerprint contract (read before touching the payload)
  #
  # The server fingerprints on md5(error_class|first_line_of_message[:160]|agent_mode)
  # and dedups per (instance, fingerprint) in a 10-minute window. So
  # `error_message` carries the exception message and NOTHING ELSE. Prepending
  # the request path or a timestamp gives every single occurrence its own
  # fingerprint, which silently destroys clustering and defeats the spike->SMS
  # alerting built on top of it. Request context rides in `traceback` instead,
  # as a key: value header block above the backtrace.
  #
  # == Privacy
  #
  # Never send params, headers, cookies, session, or ENV. Only the exception
  # class, its message, a backtrace slice, and the request method + path. Note
  # `path` and not `fullpath`: the query string can carry tokens, emails and
  # other user data, and this payload must stay clean.
  class MothershipReporter
    ENDPOINT_PATH = "/api/leonardo/report_error".freeze

    # Receiver allowlists %w[llamabot rails_app frontend].
    SOURCE = "rails_app".freeze

    TIMEOUT_SECONDS = 5
    BACKTRACE_LINES = 40

    # The server truncates traceback at 5000 and message at 2000. Trim client
    # side too so we never pay to ship bytes that get thrown away.
    TRACEBACK_LIMIT = 5000
    MESSAGE_LIMIT = 2000

    # In-process sliding-window throttle. The server dedups, but a hot error
    # loop on a box shouldn't hammer the mothership network path or spawn a
    # thread per request.
    THROTTLE_MAX = 10
    THROTTLE_WINDOW = 60

    # Exceptions Rails maps to a non-5xx status are ordinary web noise —
    # RoutingError from bot scans, 404s, malformed query strings. On a public
    # Leo box those arrive constantly and would drown the fleet dashboard and
    # eat the whole throttle budget. Skipping them keys off Rails' own
    # rescue_responses table, so it stays correct as Rails evolves.
    #
    # ...with an override, because the table is not a proxy for "boring".
    # InvalidAuthenticityToken renders as 422 but is exactly the class of
    # user-visible breakage this feature was built to catch.
    ALWAYS_REPORT = %w[
      ActionController::InvalidAuthenticityToken
      ActionController::InvalidCrossOriginRequest
    ].freeze

    # Dedup marker. Set on the EXCEPTION OBJECT rather than on the Rack env,
    # because the three capture paths don't share an env: the Rails.error
    # subscriber has none at all, and the Leonardo overlay's error-page
    # middleware calls in from a different layer. The exception instance is the
    # one thing all three genuinely have in common.
    REPORTED_FLAG = :@__llama_bot_rails_reported

    # Mirrored into the env purely so it's visible when debugging a request.
    ENV_FLAG = "llama_bot_rails.error_reported".freeze

    THROTTLE_MUTEX = Mutex.new

    class << self
      # Deliver off the request thread. Set false in tests (and only in tests)
      # so delivery is observable without joining threads.
      attr_writer :async

      def async?
        @async.nil? ? true : @async
      end

      # Report an exception to the mothership. Returns the delivery Thread when
      # async, nil otherwise or when the report was skipped.
      #
      # env      - Rack env, when there is one. Used for request method/path.
      # recovered - false for unhandled crashes; true when the app carried on.
      # context  - short free-text tag naming the capture hook, for triage.
      def report_exception(exception, env: nil, recovered: false, context: nil)
        return nil unless exception.is_a?(Exception)
        return nil if already_reported?(exception)
        return nil if ignorable?(exception)

        # Local recovery feed. Tee'd in BEFORE the mothership's own guards on
        # purpose: LlamaBot polls this to notice mid-turn that the app it just
        # edited is crashing, and that has to work on a box with no telemetry
        # credentials and on one whose throttle budget is already spent.
        # ErrorLog dedups on its own marker and swallows everything internally.
        LlamaBotRails::ErrorLog.record(exception, env: env, context: context)

        return nil unless enabled?
        return nil if throttled?

        # Mark before dispatching: an exception that gets re-raised and caught
        # again upstream must not produce a second report.
        mark_reported!(exception, env)

        # Snapshot the config HERE, on the request thread, and hand it to the
        # sender. Re-reading ENV inside the delivery thread would let a payload
        # built for one instance be shipped with another instance's credentials
        # (or none) if the environment shifted in between.
        dispatch(
          build_payload(exception, env: env, recovered: recovered, context: context),
          configuration
        )
      rescue Exception => e # rubocop:disable Lint/RescueException
        # Telemetry failures are never the customer's problem. Debug level so a
        # broken mothership can't spam a box's logs either.
        log(:debug, "report_exception swallowed #{e.class}: #{e.message}")
        nil
      end

      # No-op unless the box is a managed Leo instance. Local dev and ejected
      # apps silently skip: without a token there is nothing to authenticate
      # with and nowhere legitimate to send.
      #
      # Note MOTHERSHIP_URL is effectively always set — the LlamaPress-Simple
      # skeleton's leonardo_instance.rb initializer defaults it to
      # https://llamapress.ai — so in practice the token and instance name are
      # the two that decide this.
      def enabled?
        return false if ENV["LLAMA_BOT_ERROR_TELEMETRY"].to_s.strip.downcase == "false"

        config = configuration
        !config[:url].empty? && !config[:token].empty? && !config[:instance_name].empty?
      end

      def configuration
        {
          url: ENV["MOTHERSHIP_URL"].to_s.strip,
          token: ENV["MOTHERSHIP_API_TOKEN"].to_s.strip,
          instance_name: ENV["MOTHERSHIP_INSTANCE_NAME"].to_s.strip
        }
      end

      # True for exceptions Rails renders as a non-5xx page (see ALWAYS_REPORT
      # for the deliberate exceptions to this rule).
      def ignorable?(exception)
        return false if ALWAYS_REPORT.include?(exception.class.name)

        status = rescue_response_status(exception)
        !status.nil? && status < 500
      end

      def build_payload(exception, env: nil, recovered: false, context: nil)
        {
          instance_name: configuration[:instance_name],
          error_class: exception.class.name,
          # Message ONLY. See "The fingerprint contract" above before adding
          # anything to this line.
          #
          # Stripped because some Rails exceptions (PendingMigrationError is the
          # one that matters here) begin with blank lines. The server
          # fingerprints and displays the FIRST line, so unstripped they arrive
          # as an empty headline on the dashboard.
          error_message: exception.message.to_s.strip[0, MESSAGE_LIMIT],
          traceback: build_traceback(exception, env: env, context: context)[0, TRACEBACK_LIMIT],
          source: SOURCE,
          recovered: !!recovered,
          occurred_at: Time.now.utc.iso8601
        }
      end

      def reset_throttle!
        THROTTLE_MUTEX.synchronize { @sent_at = [] }
        nil
      end

      # Ship a pre-built, non-exception report through the same endpoint, auth, timeouts
      # and fire-and-forget semantics as report_exception. Added for the periodic
      # storage-integrity check (SI#327), which reports a MEASUREMENT rather than a crash
      # and so has no exception object to hand to report_exception.
      #
      # Callers own the fingerprint here: an exception's is derived server-side from
      # class|message|mode, but a health report must dedupe per box+condition rather than
      # per message, or a changing count would look like a brand-new incident every run.
      #
      # Deliberately skips throttled?: this runs a few times a day, and a durability check
      # silently dropped because a crash loop spent the budget is a check that does not
      # exist. It stays subject to enabled? and to every swallow-everything guarantee.
      def report_payload(instance_name:, error_class:, error_message:, source:,
                         recovered: false, fingerprint: nil, traceback: nil)
        return nil unless enabled?

        payload = {
          instance_name: instance_name,
          error_class: error_class,
          error_message: error_message.to_s[0, MESSAGE_LIMIT],
          traceback: traceback.to_s[0, TRACEBACK_LIMIT],
          source: source,
          recovered: !!recovered,
          occurred_at: Time.now.utc.iso8601
        }
        payload[:fingerprint] = fingerprint if fingerprint

        dispatch(payload, configuration)
      rescue Exception => e # rubocop:disable Lint/RescueException
        log(:debug, "report_payload swallowed #{e.class}: #{e.message}")
        nil
      end

      # Public so sibling telemetry (StorageIntegrity) shares the same quiet,
      # never-spam-the-box logging discipline instead of inventing its own.
      def log(level, message)
        return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

        Rails.logger.public_send(level, "[[LlamaBot]] MothershipReporter: #{message}")
      rescue StandardError
        nil
      end

      private

      def dispatch(payload, config)
        return Thread.new { deliver_safely(payload, config) } if async?

        deliver_safely(payload, config)
        nil
      end

      def deliver_safely(payload, config)
        deliver(payload, config)
      rescue Exception => e # rubocop:disable Lint/RescueException
        log(:debug, "delivery failed #{e.class}: #{e.message}")
        nil
      end

      def deliver(payload, config)
        uri = URI("#{config[:url].chomp('/')}#{ENDPOINT_PATH}")

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")
        http.open_timeout = TIMEOUT_SECONDS
        http.read_timeout = TIMEOUT_SECONDS
        http.write_timeout = TIMEOUT_SECONDS if http.respond_to?(:write_timeout=)

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request["Authorization"] = "Bearer #{config[:token]}"
        request.body = payload.to_json

        response = http.request(request)
        unless (200..299).cover?(response.code.to_i)
          log(:warn, "mothership rejected report (HTTP #{response.code})")
        end
        nil
      end

      def throttled?
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        THROTTLE_MUTEX.synchronize do
          @sent_at ||= []
          @sent_at.reject! { |at| now - at > THROTTLE_WINDOW }
          next true if @sent_at.size >= THROTTLE_MAX

          @sent_at << now
          false
        end
      end

      # Walk the ancestry: rescue_responses is keyed by exact class name, so a
      # subclass of RoutingError would otherwise look unmapped. Uses key? rather
      # than [] because the table has a default of :internal_server_error, which
      # would make every lookup hit on the first ancestor.
      def rescue_response_status(exception)
        return nil unless defined?(ActionDispatch::ExceptionWrapper)

        table = ActionDispatch::ExceptionWrapper.rescue_responses
        exception.class.ancestors.each do |ancestor|
          name = ancestor.name
          next if name.nil? || !table.key?(name)

          return Rack::Utils.status_code(table[name])
        end
        nil
      rescue StandardError
        nil
      end

      def build_traceback(exception, env: nil, context: nil)
        request = rack_request(env)

        header = {
          "method" => request&.request_method,
          # path, NOT fullpath — see the Privacy note in the class docs.
          "path" => request&.path,
          "request_id" => (env["action_dispatch.request_id"] if env.is_a?(Hash)),
          "rails_env" => rails_env,
          "gem_version" => LlamaBotRails::VERSION,
          "app_version" => app_version,
          "hook" => context
        }.reject { |_k, v| v.nil? || v.to_s.empty? }

        lines = header.map { |k, v| "#{k}: #{v}" }

        if (cause = exception.cause)
          lines << "cause: #{cause.class.name}: #{cause.message.to_s.lines.first.to_s.strip}"
        end

        (lines + [ "" ] + backtrace_lines(exception)).join("\n")
      end

      def backtrace_lines(exception)
        raw = exception.backtrace || []
        cleaned =
          begin
            if defined?(Rails) && Rails.respond_to?(:backtrace_cleaner)
              Rails.backtrace_cleaner.clean(raw)
            else
              []
            end
          rescue StandardError
            []
          end

        # The cleaner strips gem frames, which can empty out an exception raised
        # entirely inside a gem. Fall back to raw so we never ship a blank one.
        lines = cleaned.empty? ? raw : cleaned
        lines.first(BACKTRACE_LINES)
      end

      def rack_request(env)
        return nil unless env.is_a?(Hash)

        Rack::Request.new(env)
      rescue StandardError
        nil
      end

      def rails_env
        Rails.env.to_s if defined?(Rails) && Rails.respond_to?(:env)
      rescue StandardError
        nil
      end

      def app_version
        LlamaBotRails.app_version if LlamaBotRails.respond_to?(:app_version)
      rescue StandardError
        nil
      end

      def already_reported?(exception)
        exception.instance_variable_defined?(REPORTED_FLAG)
      rescue StandardError
        false
      end

      def mark_reported!(exception, env)
        # Frozen exceptions raise here; that only costs us dedup, not the report.
        begin
          exception.instance_variable_set(REPORTED_FLAG, true)
        rescue StandardError
          nil
        end
        env[ENV_FLAG] = true if env.is_a?(Hash)
        nil
      end

    end
  end
end
