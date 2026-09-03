module LlamaBotRails
  # Drives the shared "Inbox" tab bar (see views/llama_bot_rails/shared/_inbox_nav).
  #
  # "Inbox" is a navigation group only — the five features keep their own tables,
  # models and routes. Nothing here should ever merge them.
  module InboxHelper
    # `controller` is the engine controller name that owns the tab, and is what
    # decides which tab renders as active.
    #
    # `ability` gates the tab: nil means everyone sees it. Only Tickets is gated
    # — it is an internal engineering surface, and the other four either are
    # already per-person (Messages, Notifications sit behind sign-in and send a
    # visitor to the sign-in page, which is the right destination) or are open
    # by design (Feedback, Requests).
    # Messages is deliberately first. It is the one Inbox surface everybody has
    # (Tickets is engineers-only) and the one with unread state waiting on the
    # visitor, so it is both the tab order and — because InboxController lands
    # on the first permitted tab — where the chat UI's Inbox tab opens.
    INBOX_TABS = [
      { label: "Messages",      controller: "conversations",  icon: "fa-envelope",  path_helper: :conversations_path,  ability: nil },
      { label: "Tickets",       controller: "tickets",        icon: "fa-ticket",    path_helper: :tickets_path,        ability: :view_tickets },
      { label: "Feedback",      controller: "user_feedbacks", icon: "fa-comments",  path_helper: :user_feedbacks_path, ability: nil },
      { label: "Requests",      controller: "user_requests",  icon: "fa-lightbulb", path_helper: :user_requests_path,  ability: nil },
      { label: "Notifications", controller: "notifications",  icon: "fa-bell",      path_helper: :notifications_path,  ability: nil }
    ].freeze

    def inbox_tabs
      INBOX_TABS.select { |tab| inbox_tab_permitted?(tab) }.map do |tab|
        tab.merge(href: public_send(tab[:path_helper]), active: inbox_tab_active?(tab[:controller]))
      end
    end

    # Fails closed: a gated tab stays hidden unless something can actually
    # answer the permission question. Every Inbox controller includes
    # Authorizable, so `can?` is there in real requests; anywhere else, not
    # showing an engineering surface is the safe way to be wrong.
    #
    # The `true` second argument matters: Authorizable makes `can?` a
    # helper_method (public on the view) but leaves it PRIVATE on the
    # controller, and a bare respond_to? ignores private methods. Without it
    # this hid the Tickets tab from engineers too, on every page.
    def inbox_tab_permitted?(tab)
      ability = tab[:ability]
      return true if ability.nil?

      respond_to?(:can?, true) && can?(ability)
    end

    def inbox_tab_active?(controller)
      current_inbox_controller.to_s == controller.to_s
    end

    # Wrapped rather than calling `controller_name` inline so view specs can stub
    # the current page without booting a real controller.
    def current_inbox_controller
      controller&.controller_name
    end

    # Unread direct messages for the signed-in user, for the red badge on the
    # Messages tab. Counts only 'new_message' notifications — the badge must not
    # light up for a feedback mention, which lives on the Notifications tab.
    #
    # Rendered server-side so the badge is correct on first paint; the unread
    # bridge (shared/_parent_unread_bridge) then keeps it live from the same
    # endpoint that feeds the chat UI's tab badge.
    #
    # Returns 0 for signed-out or pre-migration host apps: the tab bar renders on
    # every Inbox page, and no badge is a better failure than a 500.
    def inbox_unread_message_count
      user = respond_to?(:current_llama_user, true) ? current_llama_user : nil
      return 0 unless user

      LlamaBotRails::Notification.unread_message_count_for(user.id)
    rescue StandardError
      0
    end
  end
end
