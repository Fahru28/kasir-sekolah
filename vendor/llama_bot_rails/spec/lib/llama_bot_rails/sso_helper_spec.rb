require 'rails_helper'

# Unified Login — the URL builder behind the "Sign in with your LlamaPress.ai
# account" CTA (rendered by app/views/llama_bot_rails/_sign_in_with_llamapress).
# The guard (both env values present, else nil) is what makes the CTA inert-safe
# on self-hosted apps.
RSpec.describe LlamaBotRails::SsoHelper do
  describe '.sign_in_url' do
    it 'builds the mothership /sso/leo/<instance> URL when both values are present' do
      url = described_class.sign_in_url(
        mothership_url: "https://llamapress.ai", instance_name: "my-box"
      )
      expect(url).to eq("https://llamapress.ai/sso/leo/my-box")
    end

    it 'strips a trailing slash from the mothership URL' do
      url = described_class.sign_in_url(
        mothership_url: "https://llamapress.ai/", instance_name: "my-box"
      )
      expect(url).to eq("https://llamapress.ai/sso/leo/my-box")
    end

    it 'returns nil when the mothership URL is missing or blank (self-hosted)' do
      expect(described_class.sign_in_url(mothership_url: nil, instance_name: "my-box")).to be_nil
      expect(described_class.sign_in_url(mothership_url: "  ", instance_name: "my-box")).to be_nil
    end

    it 'returns nil when the instance name is missing or blank' do
      expect(described_class.sign_in_url(mothership_url: "https://llamapress.ai", instance_name: nil)).to be_nil
      expect(described_class.sign_in_url(mothership_url: "https://llamapress.ai", instance_name: "  ")).to be_nil
    end

    it 'reads MOTHERSHIP_URL / MOTHERSHIP_INSTANCE_NAME from ENV by default' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("MOTHERSHIP_URL").and_return("https://llamapress.ai")
      allow(ENV).to receive(:[]).with("MOTHERSHIP_INSTANCE_NAME").and_return("env-box")

      expect(described_class.sign_in_url).to eq("https://llamapress.ai/sso/leo/env-box")
    end
  end

  # cta_html is the cold-boot-safe entry point (a class method, not a lazily
  # resolved engine view partial). It builds the same markup the partial did.
  describe '.cta_html' do
    context 'on a mothership-managed instance' do
      before do
        allow(described_class).to receive(:sign_in_url)
          .and_return("https://llamapress.ai/sso/leo/my-box")
      end

      it 'returns the CTA button with id, target=_top and the SSO href' do
        html = described_class.cta_html
        expect(html).to include('id="lp-sso-cta"')
        expect(html).to include('target="_top"')
        expect(html).to include('href="https://llamapress.ai/sso/leo/my-box"')
        expect(html).to include("Sign in with your LlamaPress.ai account")
      end

      it 'includes the frame-aware surface-routing script' do
        html = described_class.cta_html
        expect(html).to include("window.self === window.top")
        expect(html).to include("surface=rails_app")
      end

      it 'returns an html_safe string' do
        expect(described_class.cta_html).to be_html_safe
      end
    end

    context 'on a self-hosted instance (sign_in_url nil)' do
      before { allow(described_class).to receive(:sign_in_url).and_return(nil) }

      it 'returns a blank html_safe string (no CTA)' do
        expect(described_class.cta_html).to eq("")
        expect(described_class.cta_html).to be_html_safe
      end
    end

    it 'HTML-escapes the URL into the href' do
      allow(described_class).to receive(:sign_in_url)
        .and_return("https://x.test/sso/leo/a&b")
      expect(described_class.cta_html).to include("a&amp;b")
    end
  end
end
