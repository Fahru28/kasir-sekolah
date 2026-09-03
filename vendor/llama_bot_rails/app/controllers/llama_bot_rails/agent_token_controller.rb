module LlamaBotRails
  # GET /llama_bot/agent/token
  #
  # Mints the short-lived, per-user token that the LlamaBot agent presents back to this
  # app (see AgentAuth). It exists for one reason: the LlamaBot chat UI runs on a
  # DIFFERENT ORIGIN than this Rails app, so it cannot read this app's session cookie
  # and has no other way to prove who the user is. The browser fetches a token here
  # (with credentials), hands it to the agent, and the agent presents it on every
  # request — so Rails resolves `current_user` normally and the app's own gates
  # (llama_bot_allow, Pundit) apply unchanged.
  #
  # SECURITY — three rules this endpoint lives or dies by:
  #
  # 1. DEVISE SESSION ONLY. It must NEVER accept an agent token as proof of identity.
  #    AgentAuth aliases `authenticate_user!` to accept agent tokens, so calling that
  #    here would let a valid token mint a fresh one indefinitely — turning a 30-minute
  #    credential into permanent access. Hence: no `include AgentAuth`, and we read
  #    warden DIRECTLY rather than trusting any inherited auth helper that a future
  #    refactor might re-alias.
  #
  # 2. NEVER echo an arbitrary Origin back with Allow-Credentials. That combination
  #    lets ANY site read this response using the visitor's cookies — i.e. steal their
  #    token. The origin is matched against an explicit allowlist (see allowed_origin?).
  #
  # 3. The response body is a bearer credential. It is never cached.
  class AgentTokenController < ApplicationController
    # Deliberately NOT `include LlamaBotRails::AgentAuth` — see rule 1 above.

    TOKEN_TTL = 30.minutes

    before_action :set_cors_headers

    # The browser calls this cross-origin with `credentials: 'include'`. A plain GET
    # with no custom headers is a CORS "simple request", so there is no preflight to
    # answer — but we handle OPTIONS anyway in case a caller adds a header later.
    def options
      head :no_content
    end

    def show
      user = devise_session_user

      if user.nil?
        # Not signed in. This is a normal state (the user simply hasn't logged into
        # the Rails app yet), not an error worth alarming about.
        return render(json: {
          error: "Not signed in",
          hint: "Sign in to this Rails app, then reload the chat."
        }, status: :unauthorized)
      end

      response.headers["Cache-Control"] = "no-store"

      render json: {
        api_token: Rails.application.message_verifier(:llamabot_ws).generate(
          { session_id: SecureRandom.uuid, user_id: user.id },
          expires_in: TOKEN_TTL
        ),
        expires_in: TOKEN_TTL.to_i
      }
    end

    private

    # Read warden directly instead of `current_user`/`authenticate_user!`: those are
    # exactly what AgentAuth aliases to also accept agent tokens (rule 1). Going
    # straight to the session source means this endpoint keeps its guarantee even if
    # the surrounding auth wiring changes.
    def devise_session_user
      warden = request.env["warden"]
      return nil unless warden&.authenticated?
      warden.user
    end

    def set_cors_headers
      origin = request.headers["Origin"]
      return if origin.blank?
      return unless allowed_origin?(origin)

      response.headers["Access-Control-Allow-Origin"] = origin
      response.headers["Access-Control-Allow-Credentials"] = "true"
      # This response varies by Origin; without Vary a shared cache could hand one
      # origin's response to another.
      response.headers["Vary"] = "Origin"
    end

    # Two ways to be allowed: an exact configured origin, or the naming convention.
    #
    # Matching is always on the FULL HOST, never a prefix/suffix test — `end_with?`
    # style checks are the classic CORS bypass ("evil-llamapress-dev.llamapress.ai"
    # would sail through one).
    def allowed_origin?(origin)
      return true if configured_ui_origins.include?(origin)

      uri = begin
        URI.parse(origin)
      rescue URI::InvalidURIError
        nil
      end
      return false if uri.nil? || uri.host.blank?
      return false unless %w[http https].include?(uri.scheme)

      uri.host == conventional_ui_host
    end

    # Explicit config, for deployments that don't follow the naming convention.
    # Comma-separated, e.g. "https://chat.example.com,https://staging.example.com".
    def configured_ui_origins
      origins = []
      if ENV["LLAMABOT_UI_ORIGIN"].present?
        origins.concat(ENV["LLAMABOT_UI_ORIGIN"].split(",").map(&:strip))
      end
      origins << "http://localhost:8000" # local dev: Rails :3000, LlamaBot UI :8000
      origins
    end

    # Convention: the LlamaBot UI is this app's host WITHOUT the "rails-" prefix.
    # Mirrors getRailsUrl() in the chat frontend, which builds the Rails URL as
    # "https://rails-" + its own host. So rails-foo.example.com -> foo.example.com.
    #
    # Deliberately compares HOST only, ignoring scheme: behind a TLS-terminating proxy
    # `request.protocol` reports "http://" unless X-Forwarded-Proto is honored, so
    # building an expected origin string from it would silently fail to match the
    # browser's "https://..." Origin — a maddening, invisible CORS break. The host is
    # the part that actually establishes trust here; we echo back the browser's own
    # Origin only after confirming that host matches.
    def conventional_ui_host
      return nil unless request.host.start_with?("rails-")
      request.host.sub(/\Arails-/, "")
    end
  end
end
