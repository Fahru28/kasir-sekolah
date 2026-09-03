require "rails_helper"
require "llama_bot_rails/storage_integrity"

# Mothership SI#327 — the fleet-wide attachment-durability incident.
#
# Seven paying customers had 481 unreachable attachments; one box had been broken for
# three months. Nothing noticed, because nothing anywhere in the fleet ever compared an
# active_storage_blobs row against a file on disk. This is that check.
RSpec.describe LlamaBotRails::StorageIntegrity do
  # A stand-in for ActiveStorage's service: exist? is the only method the check uses.
  # The real one must NOT be exercised over HTTP — see the deadlock note in the class.
  def service(present_keys:, root: "/rails/storage", raises: false)
    Class.new do
      define_method(:root) { root }
      define_method(:exist?) do |key|
        raise "boom" if raises

        present_keys.include?(key)
      end
    end.new
  end

  def blob(key, svc)
    instance_double("ActiveStorage::Blob", key: key, service: svc)
  end

  describe ".scan" do
    it "counts blobs whose file is missing from the configured service" do
      svc = service(present_keys: %w[a c])
      result = described_class.scan(blobs: [blob("a", svc), blob("b", svc), blob("c", svc)])

      expect(result[:total]).to eq(3)
      expect(result[:missing]).to eq(1)
      expect(result[:root]).to eq("/rails/storage")
    end

    it "reports a clean box as recovered with nothing missing" do
      svc = service(present_keys: %w[a b])
      result = described_class.scan(blobs: [blob("a", svc), blob("b", svc)])

      expect(result[:missing]).to eq(0)
      expect(result[:recovered]).to be(true)
    end

    # Gotcha 1 from the ticket: exist? only checks the CURRENTLY CONFIGURED root, so
    # "100% missing" reads identically whether files were deleted or the app is merely
    # pointed at the wrong directory. ~243 of the "lost" files were never deleted. The
    # root has to ride along or the mothership cannot tell a config fix from a restore.
    it "always reports the resolved service root so misconfiguration is distinguishable" do
      svc = service(present_keys: [], root: "/rails/tmp/storage")
      result = described_class.scan(blobs: [blob("a", svc)])

      expect(result[:root]).to eq("/rails/tmp/storage")
      expect(result[:message]).to include("/rails/tmp/storage")
    end

    # A telemetry check must never be the thing that breaks a customer's app.
    it "treats an exploding service as present rather than raising" do
      svc = service(present_keys: [], raises: true)
      result = described_class.scan(blobs: [blob("a", svc)])

      expect(result[:missing]).to eq(0)
    end

    it "stops at the sample limit so a 50k-blob box does not stall" do
      svc = service(present_keys: [])
      blobs = Array.new(10) { |i| blob("k#{i}", svc) }
      result = described_class.scan(blobs: blobs, limit: 4)

      expect(result[:total]).to eq(4)
      expect(result[:sampled]).to be(true)
    end
  end

  describe ".fingerprint" do
    it "is stable for the same box and root so rollups dedupe instead of spamming" do
      a = described_class.fingerprint("leo-abc", "/rails/storage")
      b = described_class.fingerprint("leo-abc", "/rails/storage")
      expect(a).to eq(b)
    end

    it "changes when the root changes, so a reconfigured box reports as new" do
      a = described_class.fingerprint("leo-abc", "/rails/storage")
      b = described_class.fingerprint("leo-abc", "/rails/tmp/storage")
      expect(a).not_to eq(b)
    end
  end

  describe ".report!" do
    it "sends storage_integrity to the existing receiver, never a new endpoint" do
      svc = service(present_keys: [])
      allow(LlamaBotRails::MothershipReporter).to receive(:enabled?).and_return(true)
      allow(LlamaBotRails::MothershipReporter).to receive(:configuration)
        .and_return({ url: "https://llamapress.ai", token: "t", instance_name: "leo-abc" })

      expect(LlamaBotRails::MothershipReporter).to receive(:report_payload) do |payload|
        expect(payload[:source]).to eq("storage_integrity")
        expect(payload[:error_class]).to eq("ActiveStorage::MissingFiles")
        expect(payload[:error_message]).to match(%r{1 of 1 blobs have no file \(root=/rails/storage\)})
        expect(payload[:recovered]).to be(false)
        expect(payload[:fingerprint]).to be_present
      end

      described_class.report!(blobs: [blob("a", svc)])
    end

    it "still reports a healthy box, marked recovered, so silence means 'not running'" do
      svc = service(present_keys: %w[a])
      allow(LlamaBotRails::MothershipReporter).to receive(:enabled?).and_return(true)
      allow(LlamaBotRails::MothershipReporter).to receive(:configuration)
        .and_return({ url: "https://llamapress.ai", token: "t", instance_name: "leo-abc" })

      expect(LlamaBotRails::MothershipReporter).to receive(:report_payload) do |payload|
        expect(payload[:recovered]).to be(true)
      end

      described_class.report!(blobs: [blob("a", svc)])
    end

    it "does nothing at all on a box with no telemetry credentials" do
      svc = service(present_keys: [])
      allow(LlamaBotRails::MothershipReporter).to receive(:enabled?).and_return(false)

      expect(LlamaBotRails::MothershipReporter).not_to receive(:report_payload)
      expect { described_class.report!(blobs: [blob("a", svc)]) }.not_to raise_error
    end
  end
end
