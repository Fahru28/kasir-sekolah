require "rails_helper"

# Mothership SI#342 — the engine must never hand a Rails debug page to a fetch() caller.
#
# Leo boxes run RAILS_ENV=development with consider_all_requests_local=true. When Devise
# :timeoutable signed the user out mid-page and the feedback POST arrived with the now-stale
# CSRF token, LlamaBotRails::ApplicationController had no rescue_from, so Rails answered with
# the full HTML debug page. The widget's fetch() got markup where JSON belonged and could
# only show the user "Status: 422".
RSpec.describe "session expiry returns JSON, not a debug page", type: :request do
  controller_source = LlamaBotRails::Engine.root
    .join("app/controllers/llama_bot_rails/application_controller.rb").read

  it "rescues InvalidAuthenticityToken instead of letting Rails render it" do
    expect(controller_source).to include("rescue_from ActionController::InvalidAuthenticityToken")
  end

  it "answers JSON callers with a structured, machine-readable error" do
    expect(controller_source).to match(/session_expired/),
      "the widget keys on this to know it should refresh the token and retry"
    expect(controller_source).to match(/format\.json/)
  end

  it "keeps the 422 status the client already keys on" do
    expect(controller_source).to match(/:unprocessable_entity/)
  end

  it "still does something sensible for a normal browser navigation" do
    expect(controller_source).to match(/format\.any/)
    expect(controller_source).to match(/redirect_back/)
  end
end
