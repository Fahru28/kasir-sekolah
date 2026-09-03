require "rails_helper"

# Unified Login CTA partial — regression guard for:
#   Fix 1: the ERB doc comment must NOT leak onto the page (an inner `%` + `>`
#          would close the `<%#` comment early — that was the original bug).
#   Fix 2: frame-aware routing — a standalone Rails app appends surface=rails_app
#          (land back on Rails); framed stays chat.
# Behavior is also verified end-to-end by rendering the partial in a real app
# container; this spec locks it so a future edit can't silently regress it.
RSpec.describe "llama_bot_rails/sign_in_with_llamapress", type: :view do
  context "on a mothership-managed instance (sign_in_url present)" do
    before do
      allow(LlamaBotRails::SsoHelper).to receive(:sign_in_url)
        .and_return("https://llamapress.ai/sso/leo/my-box")
      render partial: "llama_bot_rails/sign_in_with_llamapress"
    end

    it "renders the CTA link with id, target=_top and the SSO url" do
      expect(rendered).to include('id="lp-sso-cta"')
      expect(rendered).to include('target="_top"')
      expect(rendered).to include("https://llamapress.ai/sso/leo/my-box")
      expect(rendered).to include("Sign in with your LlamaPress.ai account")
    end

    it "Fix 1: does not leak the ERB doc comment onto the page" do
      expect(rendered).not_to include("Ships in the gem")
      expect(rendered).not_to include("%>")
    end

    it "Fix 2: includes the frame-aware surface-routing script" do
      expect(rendered).to include("window.self === window.top")
      expect(rendered).to include("surface=rails_app")
    end
  end

  context "on a self-hosted instance (sign_in_url nil)" do
    before do
      allow(LlamaBotRails::SsoHelper).to receive(:sign_in_url).and_return(nil)
      render partial: "llama_bot_rails/sign_in_with_llamapress"
    end

    it "renders nothing — no CTA, no script" do
      expect(rendered.strip).to be_empty
    end
  end
end
