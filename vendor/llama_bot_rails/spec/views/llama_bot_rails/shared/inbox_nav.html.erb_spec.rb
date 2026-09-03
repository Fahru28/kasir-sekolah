require "rails_helper"
require_relative "../../../support/feedback_tables"

# The shared "Inbox" tab bar rendered by layouts/llama_bot_rails/inbox.
#
# "Inbox" is a navigation group only: the five features keep their own tables and
# routes. These specs lock the navigation contract (five tabs, one active) without
# asserting on styling text, which is free to change.
RSpec.describe "llama_bot_rails/shared/_inbox_nav", type: :view do
  # At runtime the engine mixes its own helpers and routes into the view. A view
  # spec renders against the host app, so wire both up by hand.
  before do
    view.singleton_class.include(LlamaBotRails::Engine.routes.url_helpers)
    view.singleton_class.include(LlamaBotRails::InboxHelper)
  end

  # Tab label => the engine controller that owns it. Messages is first: it is the
  # one surface everybody has, and InboxController lands on the first tab.
  TABS = {
    "Messages" => "conversations",
    "Tickets" => "tickets",
    "Feedback" => "user_feedbacks",
    "Requests" => "user_requests",
    "Notifications" => "notifications"
  }.freeze

  # `can?` comes from the Authorizable controller concern, so it is not defined
  # on a bare view. Default to permitting everything; the gating examples below
  # override it.
  def stub_can(&block)
    without_partial_double_verification do
      allow(view).to receive(:can?, &(block || ->(_ability, _resource = nil) { true }))
    end
  end

  def render_nav(current_controller: "tickets")
    stub_can unless view.respond_to?(:can?)
    allow(view).to receive(:current_inbox_controller).and_return(current_controller)
    render partial: "llama_bot_rails/shared/inbox_nav"
    Nokogiri::HTML.fragment(rendered)
  end

  def tab_links(fragment)
    fragment.css("a.inbox-tab")
  end

  # Read the label element rather than the link's text: the Messages tab also
  # carries an unread-count badge inside the link.
  def tab_labels(fragment)
    tab_links(fragment).map { |a| a.css(".inbox-tab-label").text.strip }
  end

  it "renders one tab link per Inbox page" do
    fragment = render_nav

    expect(tab_links(fragment).size).to eq(5)
    expect(tab_labels(fragment)).to eq(TABS.keys)
  end

  # Messages leads. The chat UI's single Inbox tab points at /inbox, which lands
  # on the first permitted tab, so this order is also the Inbox's landing page.
  it "puts Messages first" do
    expect(tab_labels(render_nav).first).to eq("Messages")
    expect(tab_links(render_nav).first["href"])
      .to eq(LlamaBotRails::Engine.routes.url_helpers.conversations_path)
  end

  it "points each tab at its own route" do
    links = tab_links(render_nav)
    hrefs = links.map { |a| a["href"] }

    expect(hrefs).to eq([
      LlamaBotRails::Engine.routes.url_helpers.conversations_path,
      LlamaBotRails::Engine.routes.url_helpers.tickets_path,
      LlamaBotRails::Engine.routes.url_helpers.user_feedbacks_path,
      LlamaBotRails::Engine.routes.url_helpers.user_requests_path,
      LlamaBotRails::Engine.routes.url_helpers.notifications_path
    ])
  end

  TABS.each do |label, controller|
    it "marks only the #{label} tab active on #{controller}" do
      links = tab_links(render_nav(current_controller: controller))
      active = links.select { |a| a["aria-current"] == "page" }

      expect(active.map { |a| a.css(".inbox-tab-label").text.strip }).to eq([label])
      expect(active.first["class"]).to include("border-blue-600")
      (links.to_a - active).each do |other|
        expect(other["class"]).not_to include("border-blue-600")
      end
    end
  end

  it "marks no tab active on a page outside the Inbox group" do
    links = tab_links(render_nav(current_controller: "projects"))

    expect(links.size).to eq(5)
    expect(links.select { |a| a["aria-current"] == "page" }).to be_empty
  end

  # The Inbox is a self-contained app: the chat UI owns moving between its own
  # tabs, so this chrome must not offer a way out. The old feedback navbar this
  # bar replaced had a "Back to App" link; it is deliberately gone.
  describe "leaving the Inbox" do
    it "offers no way out of the Inbox" do
      fragment = render_nav
      inbox_paths = LlamaBotRails::InboxHelper::INBOX_TABS
        .map { |tab| LlamaBotRails::Engine.routes.url_helpers.public_send(tab[:path_helper]) }

      # The refresh control points at the current page, so it is self-referential
      # by definition and cannot lead out of the group.
      hrefs = fragment.css("a[href]").reject { |a| a["class"].to_s.include?("inbox-refresh") }
        .map { |a| a["href"] }
      expect(hrefs).to all(be_in(inbox_paths))
    end

    it "does not link to the host application's root" do
      fragment = render_nav
      root = Rails.application.routes.url_helpers.root_path

      expect(fragment.css("a[href='#{root}']")).to be_empty
      expect(fragment.text).not_to include("Back to App")
    end

    it "names where you are without making it a link" do
      fragment = render_nav

      expect(fragment.css("header").text).to include("Inbox")
    end

    # The feedback views used to render their own `_navbar` partial. It was
    # `fixed top-0 z-40` and this header is `sticky top-0 z-40`, so the old bar
    # painted straight over the new one — the tab bar and the refresh control
    # were invisible on all six feedback pages while it survived.
    it "is the only nav bar: the old feedback navbar partial is gone" do
      expect(LlamaBotRails::Engine.root.join("app/views/llama_bot_rails/user_feedbacks/_navbar.html.erb"))
        .not_to exist

      views = LlamaBotRails::Engine.root.glob("app/views/llama_bot_rails/**/*.html.erb")
      offenders = views.select { |v| v.read.match?(/render\s+['"]navbar['"]/) }

      expect(offenders).to be_empty
    end
  end

  # Refreshing has to land you back on the page you were reading, filters and
  # all — a refresh that resets you to an unfiltered index is a worse outcome
  # than not offering one.
  describe "the refresh control" do
    def refresh_link(fragment)
      fragment.css("a.inbox-refresh")
    end

    it "renders exactly one, labelled for screen readers" do
      link = refresh_link(render_nav)

      expect(link.size).to eq(1)
      expect(link.first["aria-label"]).to eq("Refresh this page")
    end

    it "points back at the page currently being viewed" do
      controller.request.path_info = "/requests"
      controller.request.query_string = "status=pending&request_type=feature"

      expect(refresh_link(render_nav).first["href"])
        .to eq("/requests?status=pending&request_type=feature")
    end

    it "re-fetches rather than serving a cached preview" do
      expect(refresh_link(render_nav).first["data-turbo"]).to eq("false")
    end

    it "is present even when nobody is signed in" do
      stub_llama_user(nil)

      expect(refresh_link(render_nav).size).to eq(1)
    end
  end

  # current_llama_user comes from the Authorizable controller concern, so it is
  # not defined on a bare view — stub it past partial-double verification.
  def stub_llama_user(user)
    without_partial_double_verification do
      allow(view).to receive(:current_llama_user).and_return(user)
    end
  end

  context "when a llama user is signed in" do
    it "renders the user badge" do
      # id as well as email: the tab bar also asks this user for its unread count.
      stub_llama_user(double(email: "person@example.com", id: 1))

      expect(render_nav.text).to include("person@example.com")
    end
  end

  context "when no llama user is signed in" do
    it "says so instead of the badge" do
      stub_llama_user(nil)

      expect(render_nav.text).to include("Not signed in")
    end
  end

  context "when current_llama_user is not defined at all" do
    it "renders the tabs and omits the user area" do
      fragment = render_nav

      expect(tab_links(fragment).size).to eq(5)
      expect(fragment.text).not_to include("Not signed in")
    end
  end

  # The red count on the Messages tab. It is rendered server-side so it is right
  # on first paint (the unread bridge only keeps it live afterwards), and it is
  # scoped to direct messages — a feedback mention belongs on Notifications.
  describe "the unread badge" do
    def badge(fragment)
      fragment.css('[data-llamabot="inbox-nav-unread-badge"]')
    end

    def render_nav_with_unread(count)
      without_partial_double_verification do
        allow(view).to receive(:inbox_unread_message_count).and_return(count)
      end
      render_nav
    end

    it "sits inside the Messages tab and nowhere else" do
      fragment = render_nav_with_unread(3)

      expect(badge(fragment).size).to eq(1)
      messages_tab = tab_links(fragment).find { |a| a.css(".inbox-tab-label").text.strip == "Messages" }
      expect(messages_tab.css('[data-llamabot="inbox-nav-unread-badge"]')).to be_present
    end

    it "shows the count when there are unread messages" do
      node = badge(render_nav_with_unread(3)).first

      expect(node.text.strip).to eq("3")
      expect(node["class"]).not_to include("hidden")
      expect(node["aria-label"]).to eq("3 unread messages")
    end

    # An empty red dot reads as "something is wrong" rather than "nothing new".
    it "is hidden at zero" do
      node = badge(render_nav_with_unread(0)).first

      expect(node["class"]).to include("hidden")
      expect(node["aria-label"]).to be_nil
    end

    it "caps at 99+ so a large count cannot stretch the tab bar" do
      expect(badge(render_nav_with_unread(1234)).first.text.strip).to eq("99+")
    end

    # The badge is markup the live poller rewrites; it must exist even at zero,
    # or the first message to arrive would have nothing to paint into.
    it "renders the element even with no user signed in" do
      stub_llama_user(nil)

      expect(badge(render_nav).size).to eq(1)
    end
  end

  describe "#inbox_unread_message_count" do
    # Stubbing a method on the Notification class makes ActiveRecord load its
    # columns, and the dummy app's schema.rb does not carry the engine's tables.
    before { LlamaBotRails::SpecSupport::FeedbackTables.build! }

    it "counts only unread direct messages for the signed-in user" do
      stub_llama_user(double(id: 42))
      allow(LlamaBotRails::Notification).to receive(:unread_message_count_for).with(42).and_return(7)

      expect(view.inbox_unread_message_count).to eq(7)
    end

    it "is zero when nobody is signed in" do
      stub_llama_user(nil)

      expect(view.inbox_unread_message_count).to eq(0)
    end

    # The tab bar renders on every Inbox page. A host app that has not installed
    # the notifications migration must get no badge, not a 500 on every page.
    it "is zero when the count cannot be taken" do
      stub_llama_user(double(id: 1))
      allow(LlamaBotRails::Notification).to receive(:unread_message_count_for)
        .and_raise(ActiveRecord::StatementInvalid.new("no such table"))

      expect(view.inbox_unread_message_count).to eq(0)
    end
  end

  # The ticket board is an internal engineering surface. Grouping it into this
  # tab bar is what first put a link to it in front of ordinary users, so the
  # bar must not offer a tab the viewer would be bounced off.
  describe "the Tickets tab" do
    it "is shown to someone who may view tickets" do
      stub_can { |ability, _resource = nil| ability == :view_tickets }

      expect(tab_labels(render_nav(current_controller: "user_feedbacks"))).to include("Tickets")
    end

    it "is hidden from someone who may not" do
      stub_can { |ability, _resource = nil| ability != :view_tickets }
      labels = tab_labels(render_nav(current_controller: "user_feedbacks"))

      expect(labels).not_to include("Tickets")
      expect(labels).to eq(["Messages", "Feedback", "Requests", "Notifications"])
    end

    it "is hidden when nothing can answer the permission question" do
      # No `can?` at all — fail closed rather than leaking the surface.
      allow(view).to receive(:current_inbox_controller).and_return("user_feedbacks")
      render partial: "llama_bot_rails/shared/inbox_nav"

      expect(Nokogiri::HTML.fragment(rendered).css("a.inbox-tab .inbox-tab-label").map { |n| n.text.strip })
        .not_to include("Tickets")
    end

    it "does not gate the other four tabs" do
      stub_can { |_ability, _resource = nil| false }

      expect(tab_labels(render_nav(current_controller: "user_feedbacks")))
        .to eq(["Messages", "Feedback", "Requests", "Notifications"])
    end
  end
end
