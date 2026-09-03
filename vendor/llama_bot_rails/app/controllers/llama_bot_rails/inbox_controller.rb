module LlamaBotRails
  # The chat UI shows one "Inbox" tab where it used to show three (Tickets,
  # Feedback, Messages). That tab needs a single URL to point at, but the pages
  # behind it are not equally visible: Tickets is an engineering surface, so
  # landing everyone there would dead-end every non-engineer on an
  # "unauthorized" page inside their Inbox tab.
  #
  # So the tab points here, and this sends each visitor to the first page their
  # own tab bar would show them. Tab order is owned by InboxHelper::INBOX_TABS,
  # which is also what renders the bar, so the landing page can never disagree
  # with the first tab the visitor sees.
  class InboxController < ApplicationController
    include Authorizable
    include InboxHelper

    def show
      redirect_to landing_path
    end

    private

    def landing_path
      tab = InboxHelper::INBOX_TABS.find { |candidate| inbox_tab_permitted?(candidate) }

      # Every tab gated off is not a state the default permission checker can
      # produce (four of the five are ungated), but a host app is free to
      # replace that checker, and a nil here would be a 500 on the tab click.
      return llama_bot_rails.unauthorized_path unless tab

      public_send(tab[:path_helper])
    end
  end
end
