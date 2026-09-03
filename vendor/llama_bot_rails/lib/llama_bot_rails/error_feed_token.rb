require "openssl"
require "active_support/security_utils"

module LlamaBotRails
  # A box-internal credential for the crash feed (`GET /llama_bot/errors`).
  #
  # The feed is LlamaBot reading THIS box's own Rails error log so it can fix a
  # crash mid-turn. The first version gated it on the per-user agent token the
  # chat frontend mints, which turned out to be the wrong credential: that token
  # only exists when the human happens to hold a Devise session in the browser
  # tab, so the whole feature silently no-opped for anyone signed out — a
  # browser-session detail deciding whether the box can read its own log.
  #
  # Instead both containers already share SECRET_KEY_BASE (same `.env`), so each
  # side derives the same value from it. Plain HMAC-SHA256 rather than
  # ActiveSupport's MessageVerifier: the other end is Python, and `hmac` +
  # `hashlib` there reproduce this exactly, while Marshal-based signing does not.
  #
  # The token is no more privileged than SECRET_KEY_BASE itself — anyone holding
  # that already owns the app — and it never leaves the Docker network.
  class ErrorFeedToken
    PURPOSE = "llamabot-error-feed".freeze
    SCHEME = "LlamaBotFeed".freeze

    class << self
      # The value LlamaBot is expected to present, or nil when this box has no
      # shared secret (then only the per-user agent token is accepted).
      def expected
        secret = ENV["SECRET_KEY_BASE"].to_s.strip
        return nil if secret.empty?

        OpenSSL::HMAC.hexdigest("SHA256", secret, PURPOSE)
      end

      # Constant-time compare. Returns false — never raises, never degrades to
      # "anything works" — when there is no secret to compare against.
      def valid?(presented)
        presented = presented.to_s
        return false if presented.empty?

        want = expected
        return false if want.nil?

        ActiveSupport::SecurityUtils.secure_compare(presented, want)
      rescue StandardError
        false
      end
    end
  end
end
