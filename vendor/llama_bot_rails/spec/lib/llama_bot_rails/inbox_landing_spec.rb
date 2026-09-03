require "rails_helper"

# /llama_bot/inbox is the single URL the chat UI's Inbox tab points at. The five
# pages behind that tab are not equally visible, so this must never land someone
# on a page they will just be bounced off — that would put an "unauthorized"
# dead end inside the Inbox tab for every non-engineer.
RSpec.describe LlamaBotRails::InboxController do
  # Path helpers need a request to resolve against; nothing here issues one.
  let(:controller) do
    described_class.new.tap { |c| c.set_request!(ActionDispatch::TestRequest.create) }
  end

  def landing_path_when(permitted:)
    allow(controller).to receive(:can?) { |ability| permitted.include?(ability) }
    controller.send(:landing_path)
  end

  let(:routes) { LlamaBotRails::Engine.routes.url_helpers }

  # Messages leads the tab bar, so it is where the Inbox opens — for engineers
  # and everyone else alike. Tickets used to be first, which opened the Inbox on
  # an engineering surface.
  it "opens on Messages for someone who may view tickets" do
    expect(landing_path_when(permitted: [:view_tickets])).to eq(routes.conversations_path)
  end

  it "opens on Messages for everyone else too" do
    expect(landing_path_when(permitted: [])).to eq(routes.conversations_path)
  end

  # Messages is ungated today, but the landing page must follow the tab bar
  # rather than hard-code a page — a host app can replace the permission checker.
  it "falls through to the next permitted tab when Messages is gated off" do
    allow(controller).to receive(:can?).and_return(true)
    stub_const("LlamaBotRails::InboxHelper::INBOX_TABS", [
      { label: "Messages", controller: "conversations", icon: "fa-envelope",
        path_helper: :conversations_path, ability: :view_messages },
      { label: "Feedback", controller: "user_feedbacks", icon: "fa-comments",
        path_helper: :user_feedbacks_path, ability: nil }
    ])
    allow(controller).to receive(:can?) { |ability| ability != :view_messages }

    expect(controller.send(:landing_path)).to eq(routes.user_feedbacks_path)
  end

  # A host app can replace the permission checker entirely, and a nil tab here
  # would 500 on the tab click rather than refusing cleanly.
  it "refuses cleanly when every tab is gated off" do
    allow(controller).to receive(:can?).and_return(false)
    stub_const("LlamaBotRails::InboxHelper::INBOX_TABS", [
      { label: "Tickets", controller: "tickets", icon: "fa-ticket",
        path_helper: :tickets_path, ability: :view_tickets }
    ])

    expect(controller.send(:landing_path)).to eq(routes.unauthorized_path)
  end

  it "lands on the same page the tab bar renders first" do
    allow(controller).to receive(:can?).and_return(true)
    first_tab = LlamaBotRails::InboxHelper::INBOX_TABS.first

    expect(controller.send(:landing_path))
      .to eq(routes.public_send(first_tab[:path_helper]))
  end
end
