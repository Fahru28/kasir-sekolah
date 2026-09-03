require "rails_helper"

# Guards the wiring between the five Inbox pages and the shared layout that
# carries the tab bar. Without this, dropping a `layout` declaration would make
# the tab bar silently vanish from a page and no other spec would notice.
RSpec.describe "the Inbox layout", type: :view do
  LAYOUT = "llama_bot_rails/inbox".freeze

  INBOX_CONTROLLERS = [
    LlamaBotRails::TicketsController,
    LlamaBotRails::UserFeedbacksController,
    LlamaBotRails::UserRequestsController,
    LlamaBotRails::ConversationsController,
    LlamaBotRails::NotificationsController
  ].freeze

  def resolved_layout(controller_class)
    controller = controller_class.new
    controller.send(:_layout, controller.lookup_context, [:html], false)
  end

  describe "which pages use it" do
    INBOX_CONTROLLERS.each do |controller_class|
      it "#{controller_class.name.demodulize} renders inside it" do
        expect(resolved_layout(controller_class)).to eq(LAYOUT)
      end
    end

    # Not tabs of their own, but reachable from inside the Inbox (Tags from the
    # Requests and Feedback dashboards, Projects from the ticket views). With
    # `layout false` they were one-way doors: no tab bar, no way back.
    [LlamaBotRails::TagsController, LlamaBotRails::ProjectsController].each do |controller_class|
      it "#{controller_class.name.demodulize} keeps the Inbox chrome so it is not a dead end" do
        expect(resolved_layout(controller_class)).to eq(LAYOUT)
      end
    end

    it "is not applied to controllers outside the Inbox group" do
      expect(resolved_layout(LlamaBotRails::ReleasesController)).to be_nil
    end
  end

  # A project page lists that project's tickets, so an open Projects controller
  # would hand out the board TicketsController refuses. Both must gate on the
  # same ability or one is a way around the other.
  describe "the ticket-board gate" do
    [LlamaBotRails::TicketsController, LlamaBotRails::ProjectsController].each do |controller_class|
      it "#{controller_class.name.demodulize} runs require_ticket_access!" do
        callbacks = controller_class._process_action_callbacks.map(&:filter)

        expect(callbacks).to include(:require_ticket_access!)
      end
    end
  end

  # At runtime the engine mixes its own helpers and routes into the view. A view
  # spec renders against the host app, so wire both up by hand.
  shared_context "engine view" do
    before do
      view.singleton_class.include(LlamaBotRails::Engine.routes.url_helpers)
      view.singleton_class.include(LlamaBotRails::InboxHelper)

      # These examples are about the layout, not about who may see which tab —
      # permit everything so the full bar renders. Gating is covered in
      # spec/views/llama_bot_rails/shared/inbox_nav.html.erb_spec.rb.
      without_partial_double_verification do
        allow(view).to receive(:can?).and_return(true)
      end
    end
  end

  describe "what it renders" do
    include_context "engine view"

    before do
      render inline: <<~ERB, layout: "layouts/#{LAYOUT}"
        <% content_for :title, "A Page Title" %>
        <% content_for :head do %><meta name="page-specific-tag"><% end %>
        <p id="page-body">page content</p>
      ERB
    end

    let(:document) { Nokogiri::HTML(rendered) }

    it "wraps the page in a single HTML document" do
      expect(rendered.scan("<!DOCTYPE html").size).to eq(1)
      expect(document.css("html").size).to eq(1)
    end

    it "renders the page content in the body" do
      expect(document.css("body #page-body").text).to eq("page content")
    end

    it "renders the tab bar above the page content" do
      expect(document.css("body a.inbox-tab").size).to eq(5)
    end

    it "takes its title from the page" do
      expect(document.css("head title").text).to eq("A Page Title")
    end

    # Pages moved their own <script>/<style>/meta tags into content_for :head
    # when their <head> was deleted; if the layout stops yielding it, that page
    # JS and CSS disappears with no other symptom.
    it "yields the page's own head tags into <head>" do
      expect(document.css("head meta[name='page-specific-tag']").size).to eq(1)
    end

    it "loads the shared CSS the pages used to each load themselves" do
      head = document.css("head").to_html

      expect(head).to include("cdn.tailwindcss.com")
      expect(head).to include("daisyui")
      expect(head).to include("font-awesome")
    end
  end

  describe "a page that sets no title" do
    include_context "engine view"

    it "falls back to a default" do
      render inline: "<p>no title</p>", layout: "layouts/#{LAYOUT}"

      expect(Nokogiri::HTML(rendered).css("head title").text).to eq("Inbox - LlamaBotRails")
    end
  end
end
