require "rails_helper"

# Pins the HTTP contract between the gem and the LlamaBot internal proxy endpoint
# (Unified Login Phase 3, Option 1). LlamaBot's POST /internal/redeem_rails_grant
# forwards to the mothership's verify_login_grant(token, "rails_app") and relays
# the result verbatim. This is the contract the LlamaBot companion PR must satisfy.
RSpec.describe LlamaBotRails::LlamaBot, ".redeem_rails_grant" do
  let(:base) { Rails.application.config.llama_bot_rails.llamabot_api_url }
  let(:endpoint) { "#{base}/internal/redeem_rails_grant" }
  let(:success_body) do
    {
      "success" => true,
      "user" => { "guid" => "g-123", "email" => "o@e.com", "name" => "O" },
      "role" => "owner",
      "permissions" => ["chat", "rails_app"]
    }
  end

  it "POSTs the token as JSON and returns [payload, nil] on success" do
    stub = stub_request(:post, endpoint)
      .with(headers: { "Content-Type" => "application/json" }, body: { token: "raw" }.to_json)
      .to_return(status: 200, body: success_body.to_json, headers: { "Content-Type" => "application/json" })

    payload, error = described_class.redeem_rails_grant("raw")

    expect(stub).to have_been_requested
    expect(error).to be_nil
    expect(payload.dig("user", "guid")).to eq("g-123")
  end

  it "returns [nil, error_code] when the proxy reports a business failure" do
    stub_request(:post, endpoint)
      .to_return(status: 410, body: { "success" => false, "error_code" => "grant_expired" }.to_json)

    payload, error = described_class.redeem_rails_grant("stale")

    expect(payload).to be_nil
    expect(error).to eq("grant_expired")
  end

  it "returns [nil, 'llamabot_unreachable'] on a transport error, never raising" do
    stub_request(:post, endpoint).to_timeout

    expect {
      payload, error = described_class.redeem_rails_grant("raw")
      expect(payload).to be_nil
      expect(error).to eq("llamabot_unreachable")
    }.not_to raise_error
  end

  it "maps a bare non-200 without a body to a redeem_failed_<code> error" do
    stub_request(:post, endpoint).to_return(status: 500, body: "")

    payload, error = described_class.redeem_rails_grant("raw")

    expect(payload).to be_nil
    expect(error).to eq("redeem_failed_500")
  end
end
