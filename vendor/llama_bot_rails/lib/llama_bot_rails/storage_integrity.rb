require "digest"
require "llama_bot_rails/mothership_reporter"

module LlamaBotRails
  # Do my blob rows still have files?
  #
  # Mothership SI#327: seven paying customers had 481 unreachable attachments and one box
  # had been broken for three months, because nothing in the fleet ever compared an
  # active_storage_blobs row against a file on disk. instance_errors had recorded ZERO
  # ActiveStorage::FileNotFoundError rows across all time, despite 606 raises on a single
  # box in one day. Backup health was green throughout. This check would have caught every
  # case, on every box, within a day.
  #
  # == Three things that cost the mothership real time; do not re-learn them
  #
  # 1. `blob.service.exist?` only checks the CURRENTLY CONFIGURED root. "100% missing"
  #    reads the same whether the files were deleted or the app is merely pointed at the
  #    wrong directory — four boxes were initially reported as total data loss when ~243
  #    of the files were sitting safely in the volume. That is the difference between
  #    "restore from backup" and "fix one config line", so the resolved root ALWAYS rides
  #    along in the payload.
  # 2. Blob key to path is sharded: <root>/<key[0,2]>/<key[2,2]>/<key>.
  # 3. NEVER iterate blobs over HTTP. On boxes with resolve_model_to_route =
  #    :rails_storage_proxy, fetching a missing blob raises inside an ActionController::Live
  #    thread holding the reloader's sharing lock; the lock is never released and the next
  #    code reload deadlocks the whole app with zero log output. That is the outage that
  #    started the investigation. This class only ever calls the service API directly.
  module StorageIntegrity
    SOURCE = "storage_integrity".freeze
    ERROR_CLASS = "ActiveStorage::MissingFiles".freeze

    # A box with 50k blobs must not stall on a telemetry check. Sampling is honest about
    # itself via the :sampled flag rather than silently reporting a partial count as total.
    DEFAULT_LIMIT = 5_000

    class << self
      # Pure and side-effect-free so it can be tested without ActiveStorage or a database.
      # `blobs` defaults to the real relation; callers inject in tests.
      def scan(blobs: nil, limit: DEFAULT_LIMIT)
        enumerator = blobs || default_blobs
        total = 0
        missing = 0
        root = nil
        sampled = false

        each_blob(enumerator) do |blob|
          if total >= limit
            sampled = true
            break
          end
          total += 1
          root ||= resolve_root(blob)
          missing += 1 unless exists?(blob)
        end

        root ||= default_root
        {
          total: total,
          missing: missing,
          root: root,
          sampled: sampled,
          recovered: missing.zero?,
          message: "#{missing} of #{total} blobs have no file (root=#{root})"
        }
      end

      # Stable per box + root: a rollup dedupes instead of spamming, but a box that gets
      # RECONFIGURED to a different root reports as a genuinely new condition.
      def fingerprint(instance_name, root)
        Digest::MD5.hexdigest("storage_integrity|#{instance_name}|#{root}")
      end

      # Fire-and-forget. Reuses the existing receiver and its auth — deliberately NOT a new
      # endpoint. A healthy box reports too (recovered: true), so silence on the dashboard
      # means "the check is not running", not "everything is fine".
      #
      # NOTE: the mothership must carry "storage_integrity" in the receiver's source
      # allowlist. Until it does, an unknown source silently degrades to "llamabot" and
      # lands in the exception stream.
      def report!(blobs: nil, limit: DEFAULT_LIMIT)
        return nil unless LlamaBotRails::MothershipReporter.enabled?

        result = scan(blobs: blobs, limit: limit)
        instance_name = LlamaBotRails::MothershipReporter.configuration[:instance_name]

        LlamaBotRails::MothershipReporter.report_payload(
          instance_name: instance_name,
          error_class: ERROR_CLASS,
          error_message: result[:message],
          source: SOURCE,
          recovered: result[:recovered],
          fingerprint: fingerprint(instance_name, result[:root]),
          traceback: traceback_for(result)
        )
        result
      rescue Exception => e # rubocop:disable Lint/RescueException
        # A durability CHECK must never be the thing that breaks the app it is checking.
        LlamaBotRails::MothershipReporter.log(:debug, "storage_integrity swallowed #{e.class}: #{e.message}")
        nil
      end

      private

      def each_blob(enumerator, &block)
        if enumerator.respond_to?(:find_each)
          enumerator.find_each(&block)
        else
          enumerator.each(&block)
        end
      end

      def default_blobs
        defined?(ActiveStorage::Blob) ? ActiveStorage::Blob : []
      end

      def default_root
        return nil unless defined?(ActiveStorage::Blob)

        ActiveStorage::Blob.service.try(:root).to_s
      rescue StandardError
        nil
      end

      def resolve_root(blob)
        blob.service.try(:root).to_s
      rescue StandardError
        nil
      end

      # A service that raises counts as PRESENT. Guessing "missing" from a transient
      # storage error would page someone about data loss that never happened.
      def exists?(blob)
        blob.service.exist?(blob.key)
      rescue StandardError
        true
      end

      def traceback_for(result)
        [
          "check: storage_integrity",
          "root: #{result[:root]}",
          "blobs_total: #{result[:total]}",
          "blobs_missing: #{result[:missing]}",
          "sampled: #{result[:sampled]}"
        ].join("\n")
      end
    end
  end
end
