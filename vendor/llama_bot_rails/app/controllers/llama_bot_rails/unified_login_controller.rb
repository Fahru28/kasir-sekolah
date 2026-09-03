module LlamaBotRails
  # Unified Login (Phase 3) — GET /llamapress_auth/consume
  #
  # Redeems a one-time login grant (minted by the mothership, threaded into the
  # chat's live-preview iframe as `?rails_token=` and forwarded here by the
  # Phase 2 frontend as `?token=`) and signs the corresponding user into the
  # host app's Devise session — so the iframe skips the Devise login wall.
  #
  # The grant is redeemed server-to-server through LlamaBot (Option 1) because
  # the Rails container holds no mothership credentials. Everything here is INERT
  # until the mothership flips `unified_login_mode`: nothing links to this route
  # until then, and a threaded token simply 404s -> login (today's behavior).
  #
  # This endpoint is NEVER a wall and NEVER an error page: any failure to redeem
  # or resolve a user degrades to a plain redirect to the sanitized `return_to`
  # (default "/"), which shows the app if a session already exists or the app's
  # normal login otherwise. The one-bounce-max retry semantics live on the
  # mothership + LlamaBot, not here.
  #
  # Inherits LlamaBotRails::ApplicationController for its X-Frame-Options strip
  # (this runs inside an iframe). It does not use the engine's agent auth.
  class UnifiedLoginController < ApplicationController
    def consume
      token = params[:token].presence
      return_to = sanitize_return_to(params[:return_to])

      # No token: someone hit the endpoint directly. Not a wall, not an error.
      return redirect_to(return_to, allow_other_host: false) if token.nil?

      payload, error_code = LlamaBotRails.grant_redeemer.call(token)

      if error_code || payload.blank?
        Rails.logger.info("[LlamaBot] unified_login consume failed: #{error_code || 'no_payload'} — degrading to #{return_to}")
        return redirect_to(return_to, allow_other_host: false)
      end

      guid = payload.dig("user", "guid") || payload.dig(:user, :guid)
      user = LlamaBotRails.guid_user_resolver.call(guid, payload)

      if user.nil?
        Rails.logger.warn("[LlamaBot] unified_login consume: no host user for guid=#{guid.inspect} — degrading to #{return_to}")
        return redirect_to(return_to, allow_other_host: false)
      end

      LlamaBotRails.sign_in_method.call(request.env, user)
      redirect_to(return_to, allow_other_host: false)
    end

    private

    # Open-redirect guard: only allow a same-origin, path-only target. Anything
    # absolute, protocol-relative, scheme-bearing, or otherwise fishy -> "/".
    def sanitize_return_to(raw)
      return "/" if raw.blank?
      return "/" unless raw.start_with?("/")   # must be an absolute path...
      return "/" if raw.start_with?("//")      # ...but not protocol-relative
      return "/" if raw.include?("\\")         # backslash tricks
      return "/" if raw.match?(/\A\/[^\/]*:/)  # e.g. "/foo:bar" scheme-ish

      uri = begin
        URI.parse(raw)
      rescue URI::InvalidURIError
        nil
      end
      return "/" if uri.nil? || uri.scheme.present? || uri.host.present?

      raw
    end
  end
end
