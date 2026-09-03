module LlamaBotRails
  module Authorizable
    extend ActiveSupport::Concern

    included do
      helper_method :current_llama_user, :can?
    end

    private

    def current_llama_user
      @current_llama_user ||= LlamaBotRails.current_user_resolver&.call(request.env)
    end

    def can?(action, resource_class = nil)
      LlamaBotRails.can?(current_llama_user, action, resource_class)
    end

    def authorize!(action, resource_class = nil)
      return if can?(action, resource_class)

      respond_to do |format|
        format.html { redirect_to llama_bot_rails.tickets_path, alert: "You are not authorized to perform this action." }
        format.json { render json: { error: "Unauthorized" }, status: :forbidden }
      end
    end

    # The app-wide access gate, for screens that do not need to know who you are
    # (Activity, Releases). It does nothing until the app is locked down, which
    # matches the host app's ApplicationController shipping with
    # authenticate_user! commented out. See
    # config.llama_bot_rails.require_authentication in engine.rb.
    def require_authentication!
      return unless LlamaBotRails.require_authentication?

      require_llama_user!
    end

    # The ticket board and the projects that own it. Shared rather than private
    # to one controller because a project page lists that project's tickets, so
    # the two surfaces have to refuse access on exactly the same condition or
    # one becomes a way around the other.
    #
    # Mirrors ActivityEventsController#require_activity_access!, including the
    # redirect target, so the engineering surfaces all refuse the same way.
    def require_ticket_access!
      return if can?(:view_tickets)

      respond_to do |format|
        format.html { redirect_to llama_bot_rails.unauthorized_path }
        format.json { render json: { error: "Unauthorized" }, status: :forbidden }
      end
    end

    # A hard identity requirement, for screens that are per-person by nature:
    # Messages, Notifications, Feedback. "Your inbox" has no meaning for a
    # visitor whose identity is unknown, so these stay behind sign-in even while
    # the app is otherwise open.
    #
    # Sends people to the engine's own sign-in page carrying the page they
    # wanted, so signing in returns them there. This used to render a "Sign In
    # Required" dead end whose only link went to the host app's root, which
    # stranded people inside the chat UI's iframe: the Messages tab ended up
    # showing the app's home page with no way back.
    def require_llama_user!
      return if current_llama_user

      respond_to do |format|
        format.html { redirect_to llama_bot_rails.sign_in_path(return_to: request.fullpath) }
        format.json { render json: { error: "Authentication required" }, status: :unauthorized }
      end
    end
  end
end
