require "rails_helper"

# Unified Login (Phase 3): GET /llamapress_auth/consume signs a user into the
# host app's Devise session from a one-time grant, so the chat's live-preview
# iframe skips the Devise wall. The route is injected at the app root by the
# engine (NOT under the /llama_bot mount). We stub the DI seams
# (grant_redeemer, guid_user_resolver, sign_in_method) so the controller logic
# is exercised without a real mothership, HTTP call, or Warden stack.
RSpec.describe "Unified Login consume", type: :request do
  let(:guid)    { "a1b2c3d4-1111-2222-3333-444455556666" }
  let(:payload) do
    {
      "user" => { "guid" => guid, "email" => "owner@example.com", "name" => "Jane" },
      "role" => "owner",
      "permissions" => ["chat", "rails_app"]
    }
  end
  let(:user) { double("User", id: 7, email: "owner@example.com") }

  def stub_redeemer(payload_val, error_val)
    allow(LlamaBotRails).to receive(:grant_redeemer)
      .and_return(->(_token) { [payload_val, error_val] })
  end

  def stub_resolver(user_val)
    allow(LlamaBotRails).to receive(:guid_user_resolver)
      .and_return(->(_guid, _payload) { user_val })
  end

  before do
    # Capture whoever gets signed in, without needing a real Warden stack.
    @signed_in = nil
    allow(LlamaBotRails).to receive(:sign_in_method)
      .and_return(->(_env, u) { @signed_in = u; true })
  end

  describe "happy path" do
    before { stub_redeemer(payload, nil); stub_resolver(user) }

    it "signs the resolved user in and redirects to the sanitized return_to" do
      get "/llamapress_auth/consume", params: { token: "raw-grant", return_to: "/dashboard" }

      expect(@signed_in).to eq(user)
      expect(response).to redirect_to("/dashboard")
    end

    it "defaults return_to to '/' when absent" do
      get "/llamapress_auth/consume", params: { token: "raw-grant" }

      expect(@signed_in).to eq(user)
      expect(response).to redirect_to("/")
    end

    it "passes the raw token to the redeemer" do
      expect(LlamaBotRails).to receive(:grant_redeemer)
        .and_return(->(token) { expect(token).to eq("raw-grant"); [payload, nil] })
      get "/llamapress_auth/consume", params: { token: "raw-grant" }
      expect(response).to redirect_to("/")
    end
  end

  describe "guid -> user mapping" do
    it "does not sign anyone in when the resolver returns nil (unknown guid)" do
      stub_redeemer(payload, nil)
      stub_resolver(nil)

      get "/llamapress_auth/consume", params: { token: "raw-grant", return_to: "/x" }

      expect(@signed_in).to be_nil
      expect(response).to redirect_to("/x")
    end

    it "hands the resolver the guid from the payload" do
      stub_redeemer(payload, nil)
      expect(LlamaBotRails).to receive(:guid_user_resolver)
        .and_return(->(g, p) { expect(g).to eq(guid); expect(p).to eq(payload); user })

      get "/llamapress_auth/consume", params: { token: "raw-grant" }
      expect(@signed_in).to eq(user)
    end
  end

  describe "redemption failures degrade gracefully (never error-page)" do
    %w[grant_expired grant_used grant_not_found bad_audience llamabot_unreachable].each do |code|
      it "redirects to return_to and signs no one in on #{code}" do
        stub_redeemer(nil, code)
        stub_resolver(user) # should never be consulted

        get "/llamapress_auth/consume", params: { token: "stale", return_to: "/back" }

        expect(@signed_in).to be_nil
        expect(response).to redirect_to("/back")
        expect(response).not_to have_http_status(:server_error)
      end
    end
  end

  describe "return_to open-redirect guard" do
    before { stub_redeemer(payload, nil); stub_resolver(user) }

    ["https://evil.com/steal", "//evil.com", "http://evil.com", "\\\\evil.com", "javascript:alert(1)"].each do |evil|
      it "rejects #{evil.inspect} and falls back to '/'" do
        get "/llamapress_auth/consume", params: { token: "raw-grant", return_to: evil }
        expect(response).to redirect_to("/")
      end
    end

    it "keeps a legitimate same-origin path" do
      get "/llamapress_auth/consume", params: { token: "raw-grant", return_to: "/projects/1?tab=x" }
      expect(response).to redirect_to("/projects/1?tab=x")
    end
  end

  describe "no token" do
    it "redirects to return_to without calling the redeemer (no 500)" do
      expect(LlamaBotRails).not_to receive(:grant_redeemer)
      get "/llamapress_auth/consume", params: { return_to: "/" }
      expect(@signed_in).to be_nil
      expect(response).to redirect_to("/")
    end
  end
end
