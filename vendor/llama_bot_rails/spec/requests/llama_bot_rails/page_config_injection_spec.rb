require "rails_helper"

# window.llamapressConfig used to be set by a single layout partial that only one
# client overlay had, so every other layout — including the base image's own
# application.html.erb — rendered pages where the feedback bubble could never
# draw (it needs feedbackBubbleEnabled && userLoggedIn). The engine now injects
# the config after the opening <head> of every HTML response instead, which no
# layout can forget.
#
# The dummy app's application.html.erb is deliberately one of those forgetful
# layouts: it has a <head> and no config anywhere.
RSpec.describe "Page config injection", type: :request do
  # Setting the real OrderedOptions (and restoring it) is closer to what a host
  # app's initializer does than stubbing method_missing.
  def with_config(**values)
    @restore ||= {}
    values.each do |key, value|
      @restore[key] = LlamaBotRails.config[key] unless @restore.key?(key)
      LlamaBotRails.config[key] = value
    end
  end

  after do
    (@restore || {}).each { |key, value| LlamaBotRails.config[key] = value }
  end

  def config_json
    body = response.body
    match = body.match(/window\.llamapressConfig = (\{.*?\});/m)
    expect(match).not_to be_nil, "no window.llamapressConfig in:\n#{body}"
    # The payload is json_escape'd (< > & become \uXXXX); JSON.parse un-escapes.
    JSON.parse(match[1])
  end

  it "injects the config into a layout that never mentions it" do
    get "/spec_page"

    expect(response).to have_http_status(:ok)
    expect(config_json).to include(
      "feedbackBubbleEnabled" => true,
      "userLoggedIn" => false
    )
  end

  it "injects immediately after <head>, before the deferred module tags" do
    get "/spec_page"

    head_at   = response.body.index("<head>")
    config_at = response.body.index("window.llamapressConfig")
    script_at = response.body.index('type="module"')

    expect(config_at).to be > head_at
    expect(config_at).to be < script_at
  end

  it "carries the app version and the releases path the bubble links to" do
    allow(LlamaBotRails).to receive(:app_version).and_return("9.9.9")

    get "/spec_page"

    expect(config_json["appVersion"]).to eq("9.9.9")
    expect(config_json["releasesUrl"]).to include("releases")
  end

  it "reports the visitor as signed in from the host app's current_user" do
    get "/spec_page", params: { signed_in: "1" }

    expect(config_json["userLoggedIn"]).to be true
  end

  it "prefers user_signed_in? when the host app is on Devise" do
    get "/spec_page_devise", params: { signed_in: "1" }
    expect(config_json["userLoggedIn"]).to be true

    get "/spec_page_devise"
    expect(config_json["userLoggedIn"]).to be false
  end

  it "honours feedback_bubble_enabled = false" do
    with_config(feedback_bubble_enabled: false)

    get "/spec_page"

    expect(config_json["feedbackBubbleEnabled"]).to be false
  end

  it "leaves a layout that already owns the config alone" do
    get "/spec_page_with_config"

    expect(response.body.scan("window.llamapressConfig").size).to eq(1)
    expect(response.body).to include("feedbackBubbleEnabled: false")
  end

  it "still injects when a layout only mentions the config in a comment" do
    get "/spec_page_mentions"

    expect(config_json).to include("feedbackBubbleEnabled" => true)
  end

  it "does nothing to a response with no <head>" do
    get "/spec_page_bare"

    expect(response.body).not_to include("window.llamapressConfig")
  end

  it "does nothing to a non-HTML response" do
    get "/spec_page_json"

    expect(response.body).to eq({ ok: true }.to_json)
  end

  it "can be switched off by the host app" do
    with_config(inject_page_config: false)

    get "/spec_page"

    expect(response.body).not_to include("window.llamapressConfig")
  end

  it "never breaks the request when the config cannot be built" do
    allow(LlamaBotRails).to receive(:app_version).and_raise("boom")

    get "/spec_page"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("hello")
    expect(response.body).not_to include("window.llamapressConfig")
  end
end
