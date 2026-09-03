require "digest"
require "time"

module LlamaBotRails
  # A small in-memory ring of the app's most recent crashes, so LlamaBot can
  # notice mid-turn that the code it just wrote broke the app and fix it before
  # handing back to the user. Read over HTTP by
  # `GET /llama_bot/errors?since=<seq>` (ErrorsController).
  #
  # Fed from MothershipReporter.report_exception, which is already the single
  # funnel every Rails exception passes through — the Rack telemetry middleware,
  # the Rails.error subscriber (so background jobs count), and the Leonardo
  # error page. Deliberately independent of mothership telemetry: a box with no
  # MOTHERSHIP_* credentials, or one whose throttle budget is spent, still has
  # to be able to fix itself.
  #
  # == Why a cursor and not a drain-on-read
  #
  # More than one consumer may poll this (a turn in progress, a future debug
  # panel), and a reader that empties the buffer steals errors from the others —
  # the mistake `get-console-logs` made in the chat frontend. Entries carry a
  # monotonic `seq`; a reader remembers the last one it saw and asks for what
  # came after.
  #
  # == Privacy
  #
  # Same rules as MothershipReporter: exception class, message, a backtrace
  # slice, and the request method + `path`. Never params, headers, cookies,
  # session, ENV, or the query string.
  class ErrorLog
    MAX_ENTRIES = 25
    BACKTRACE_LINES = 25
    MESSAGE_LIMIT = 1000

    MUTEX = Mutex.new

    # Set on the exception object itself so the same crash seen by two hooks
    # (Rack middleware AND the Rails.error subscriber) is logged once. Kept
    # separate from MothershipReporter's marker: that one is only set when a
    # report actually dispatches, so on an unmanaged box it never gets set at
    # all and would dedup nothing here.
    LOGGED_IVAR = :@__llama_bot_error_logged

    @entries = []
    @seq = 0

    class << self
      # Add one exception to the ring. Never raises: this sits on the crash path
      # of a customer request, and a bookkeeping bug here must not replace the
      # app's real exception with ours.
      def record(exception, env: nil, context: nil, now: nil)
        return nil unless exception.is_a?(Exception)
        return nil unless enabled?
        return nil if already_logged?(exception)

        mark_logged!(exception)
        entry = build_entry(exception, env: env, context: context, now: now || Time.now)
        MUTEX.synchronize { append(entry) }
        nil
      rescue Exception # rubocop:disable Lint/RescueException
        nil
      end

      # Entries recorded after +cursor+, oldest first.
      def since(cursor)
        cursor = cursor.to_i
        MUTEX.synchronize { @entries.select { |e| e[:seq] > cursor }.map { |e| public_entry(e) } }
      end

      # Entries recorded in the last +seconds+, oldest first.
      #
      # This is how a LlamaBot turn arms itself when the app is ALREADY broken —
      # the user is looking at the error page and asking for a fix, so there is
      # no "new" crash coming and a seq cursor alone would stay silent forever.
      # A window rather than the whole ring: a crash from an hour ago is not
      # what this turn is about.
      def within(seconds)
        seconds = seconds.to_f
        return [] unless seconds.positive?

        cutoff = Time.now.to_f - seconds
        MUTEX.synchronize do
          @entries.select { |e| e[:recorded_at].to_f >= cutoff }.map { |e| public_entry(e) }
        end
      end

      def latest_seq
        MUTEX.synchronize { @seq }
      end

      def reset!
        MUTEX.synchronize do
          @entries = []
          @seq = 0
        end
        nil
      end

      # Off switch for the whole feature, independent of
      # LLAMA_BOT_ERROR_TELEMETRY (which governs mothership reporting only).
      def enabled?
        ENV["LLAMA_BOT_ERROR_FEED"].to_s.strip.downcase != "false"
      end

      def build_entry(exception, env: nil, context: nil, now: Time.now)
        request = rack_request(env)
        message = exception.message.to_s.strip[0, MESSAGE_LIMIT].to_s

        {
          seq: nil, # assigned under the mutex in #append
          fingerprint: fingerprint_for(exception.class.name, message, request&.path),
          error_class: exception.class.name,
          message: message,
          method: request&.request_method,
          path: request&.path,
          context: context,
          count: 1,
          at: now.utc.iso8601,
          # Internal only — stripped by public_entry. Kept as a float so the
          # window filter never has to re-parse a timestamp.
          recorded_at: now.to_f,
          backtrace: backtrace_lines(exception)
        }
      end

      private

      # What a reader is allowed to see: the entry minus internal bookkeeping.
      def public_entry(entry)
        entry.reject { |key, _| key == :recorded_at }
      end

      # Caller holds MUTEX.
      def append(entry)
        newest = @entries.last

        # A render loop can raise the identical error hundreds of times. Collapse
        # it into a count rather than flushing everything else out of the ring —
        # but re-stamp `seq` so a reader that already consumed the first one
        # still learns it is happening again.
        if newest && newest[:fingerprint] == entry[:fingerprint]
          @seq += 1
          newest[:count] += 1
          newest[:seq] = @seq
          newest[:at] = entry[:at]
          newest[:recorded_at] = entry[:recorded_at]
          return
        end

        @seq += 1
        entry[:seq] = @seq
        @entries.push(entry)
        @entries.shift while @entries.length > MAX_ENTRIES
      end

      def fingerprint_for(error_class, message, path)
        Digest::MD5.hexdigest([ error_class, message.to_s.lines.first.to_s.strip, path ].join("|"))
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
        (cleaned.empty? ? raw : cleaned).first(BACKTRACE_LINES)
      end

      def rack_request(env)
        return nil unless env.is_a?(Hash)

        Rack::Request.new(env)
      rescue StandardError
        nil
      end

      def already_logged?(exception)
        exception.instance_variable_defined?(LOGGED_IVAR)
      rescue StandardError
        false
      end

      def mark_logged!(exception)
        # Frozen exceptions raise here; that only costs us dedup, not the entry.
        exception.instance_variable_set(LOGGED_IVAR, true)
      rescue StandardError
        nil
      end
    end
  end
end
