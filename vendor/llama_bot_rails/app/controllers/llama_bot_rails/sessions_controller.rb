module LlamaBotRails
  # A sign-in page owned by the engine, at /llama_bot/sign_in.
  #
  # Two reasons this exists rather than sending people to the host app's
  # /users/sign_in:
  #
  #   1. Every engine surface (Messages, Activity, Tickets, Feedback) is loaded
  #      in an iframe inside the chat UI. Sending an unauthenticated visitor to
  #      the host app's root left them stranded: they landed on the app's home
  #      page inside the Messages tab, with nothing to click that got them back.
  #      This controller carries a return_to through the sign-in and returns
  #      them to the page they actually asked for.
  #
  #   2. The host app owns /users/sign_in and may restyle or replace it. The
  #      engine's own surfaces need a sign-in screen whose look and wording it
  #      controls, so the experience does not change under it.
  #
  # Authentication itself is still Devise's. This controller only collects the
  # credentials and hands them to Warden, so password checks, lockouts and
  # trackable columns behave exactly as they do on the host app's own form.
  class SessionsController < ApplicationController
    include Authorizable

    layout false

    before_action :redirect_if_signed_in, only: [ :new ]

    def new
      @return_to = safe_return_to
    end

    def create
      @return_to = safe_return_to

      unless devise_available?
        @error = "This application does not use Devise, so the built-in sign-in form cannot be used."
        return render :new, status: :not_implemented
      end

      # Devise's database_authenticatable strategy refuses to look at POST params
      # unless the request opts in (Devise::Strategies::Authenticatable#
      # valid_params_request? reads this env key). Devise's own SessionsController
      # sets it via allow_params_authentication!; without it the strategy is
      # skipped, warden returns nil, and every correct password looks wrong.
      request.env["devise.allow_params_authentication"] = true

      # authenticate (no bang) returns nil on bad credentials instead of
      # throwing, which is what lets us re-render this form with an error
      # rather than bouncing to the host app's Devise failure page.
      user = warden.authenticate(scope: devise_scope)

      if user
        redirect_to @return_to
      else
        @error = "We could not sign you in. Check your email and password, then try again."
        render :new, status: :unprocessable_entity
      end
    end

    private

    def warden
      request.env["warden"]
    end

    def devise_available?
      defined?(::Devise) && warden.present?
    end

    def devise_scope
      ::Devise.default_scope
    end
    helper_method :devise_scope

    def redirect_if_signed_in
      redirect_to safe_return_to if current_llama_user
    end

    # Where to send the visitor once they are signed in.
    #
    # Only a same-origin absolute path survives. A full URL, a protocol-relative
    # "//evil.com" (or its "/\evil.com" cousin, which browsers normalize the
    # same way), or anything with control characters would turn this form into
    # an open redirect, so all of those fall back to the engine root.
    def safe_return_to
      candidate = params[:return_to].to_s

      return default_return_to if candidate.blank?
      return default_return_to unless candidate.start_with?("/")
      return default_return_to if candidate.start_with?("//", "/\\")
      return default_return_to if candidate.match?(/[\x00-\x20\x7f]/)

      candidate
    end

    # Conversations is the safest landing spot: it is the surface every signed-in
    # user can reach, unlike Tickets and Activity which are permission-gated.
    def default_return_to
      llama_bot_rails.conversations_path
    end
  end
end
