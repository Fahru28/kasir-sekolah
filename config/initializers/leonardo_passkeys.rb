# frozen_string_literal: true

# Reusable configuration layer for optional passkey (WebAuthn) authentication.
#
# Passkeys are OFF by default. A project turns them on by setting
# PASSKEYS_ENABLED=true and including PasskeyAuthenticatableUser in its User
# model (see app/models/concerns/passkey_authenticatable_user.rb). Until it
# does, sign-in behaves exactly like plain Devise.
#
# Passkeys here are always ADDITIVE -- they never replace passwords. A Leonardo
# box has no guaranteed mail delivery (dev-style environment, no delivery method,
# raise_delivery_errors off), and email is the usual passkey recovery route, so a
# passwordless-only app would lock a user out with no error anywhere. Recovery
# codes (PasskeyRecoveryCode) are the part we can actually guarantee.
module LeonardoPasskeys
  # Domains this platform serves instance apps on, most canonical first. A box
  # answers on "rails-<instance>.<domain>" for each of these.
  PLATFORM_DOMAINS = %w[
    leo.llamapress.ai
    llamapress.ai
    leo.builtwithleo.com
  ].freeze

  # A Relying Party ID is matched by SUFFIX: a passkey scoped to "llamapress.ai"
  # is offered inside every app under it. Scoping to a shared parent would hand
  # one customer's passkey to a different customer's app, so these are refused
  # as an RP ID -- the RP ID must always be the app's OWN full hostname.
  SHARED_DOMAINS = (PLATFORM_DOMAINS + %w[builtwithleo.com]).freeze

  # How many one-time recovery codes to mint per enrollment.
  RECOVERY_CODE_COUNT = 10

  # Master switch. Gate the passkey enrollment UI on this so a project can ship
  # the capability dark and flip it on per environment.
  mattr_accessor :enabled

  # Relying Party ID: the ONE hostname a passkey is bound to.
  mattr_accessor :rp_id

  # Label shown in the OS/browser passkey prompt.
  mattr_accessor :rp_name

  # Every origin this app is actually served on. Must be a LIST -- a box answers
  # on the platform hostname, the mirror domain and (once attached) the
  # customer's own domain, and a passkey registered on one is not offered on the
  # others unless they are all listed here and in /.well-known/webauthn.
  mattr_accessor :allowed_origins

  class << self
    def enabled?
      enabled
    end

    # The instance slug the mothership assigned this box. Populated by
    # config/initializers/leonardo_instance.rb from .leonardo/instance.json.
    def instance_slug(env = ENV)
      env["MOTHERSHIP_INSTANCE_NAME"].presence
    end

    # This app's own hostnames on the platform's domains. Empty when the box has
    # no instance name, which is the correct answer: we would rather configure
    # nothing than guess a hostname and bind passkeys to it.
    def platform_hostnames(env = ENV)
      slug = instance_slug(env)
      return [] if slug.blank?

      PLATFORM_DOMAINS.map { |domain| "rails-#{slug}.#{domain}" }
    end

    # Extra hostnames the app is served on -- a customer's attached domain, or a
    # local/dev host. Comma-separated.
    def custom_hostnames(env = ENV)
      split_list(env["PASSKEY_CUSTOM_DOMAINS"]).map { |value| hostname_for(value) }.compact
    end

    def shared_domain?(value)
      SHARED_DOMAINS.include?(value.to_s.strip.downcase)
    end

    # Default RP ID = this app's own full hostname, never a shared parent.
    # PASSKEY_RP_ID overrides it (a customer domain that owns the passkeys).
    def derive_rp_id(env = ENV)
      explicit = hostname_for(env["PASSKEY_RP_ID"])
      return explicit if explicit.present?

      platform_hostnames(env).first
    end

    # Default origin list = every hostname this app answers on.
    # PASSKEY_ALLOWED_ORIGINS overrides it wholesale.
    def derive_allowed_origins(env = ENV)
      explicit = split_list(env["PASSKEY_ALLOWED_ORIGINS"]).map { |value| origin_for(value) }.compact
      return explicit if explicit.any?

      (platform_hostnames(env) + custom_hostnames(env)).uniq.map { |host| "https://#{host}" }
    end

    # Body of /.well-known/webauthn. Related Origin Requests let the mirror and
    # custom domains use a passkey bound to the RP ID hostname; the spec caps it
    # at five distinct registrable domains and we use at most three.
    def related_origins
      { origins: Array(allowed_origins) }
    end

    def configure_from_env!(env = ENV)
      self.enabled = ActiveModel::Type::Boolean.new.cast(env.fetch("PASSKEYS_ENABLED", "false"))
      self.rp_id = derive_rp_id(env)
      self.rp_name = env["PASSKEY_RP_NAME"].presence || instance_slug(env).presence || "Leonardo"
      self.allowed_origins = derive_allowed_origins(env)

      validate_rp_id!
      warn_if_unconfigured!
      apply_to_webauthn!
      self
    end

    private

    # Refuse a cross-tenant RP ID. When passkeys are ON this is fatal: booting
    # with a shared RP ID would silently offer one app's passkeys inside
    # another. When they are OFF nothing is ever registered, so a warning is
    # enough and the box still boots.
    def validate_rp_id!
      return unless shared_domain?(rp_id)

      message = "LeonardoPasskeys: PASSKEY_RP_ID=#{rp_id.inspect} is a shared platform domain. " \
                "The relying party ID must be this app's own hostname, or passkeys registered " \
                "in one customer's app would be offered inside another's."
      raise message if enabled?

      Rails.logger.warn(message)
      self.rp_id = nil
    end

    # Passkeys switched on with nothing to bind them to is the other silent
    # failure: the browser prompt simply never appears. Say so at boot.
    def warn_if_unconfigured!
      return unless enabled?
      return if rp_id.present? && allowed_origins.present?

      Rails.logger.warn(
        "LeonardoPasskeys: PASSKEYS_ENABLED is on but no relying party could be derived " \
        "(rp_id=#{rp_id.inspect}, allowed_origins=#{allowed_origins.inspect}). Set PASSKEY_RP_ID " \
        "and PASSKEY_ALLOWED_ORIGINS, or passkey prompts will never appear."
      )
    end

    def apply_to_webauthn!
      return unless defined?(::WebAuthn)

      WebAuthn.configure do |config|
        # Setting more than one allowed origin REQUIRES an explicit rp_id.
        config.allowed_origins = allowed_origins.presence
        config.rp_id = rp_id if rp_id.present?
        config.rp_name = rp_name
      end
    end

    def split_list(value)
      value.to_s.split(",").map(&:strip).reject(&:empty?)
    end

    # Accepts "example.com", "https://example.com" or "https://example.com/x".
    def hostname_for(value)
      return nil if value.blank?

      candidate = value.to_s.strip
      candidate = "https://#{candidate}" unless candidate.include?("//")
      URI.parse(candidate).host&.downcase
    rescue URI::InvalidURIError
      nil
    end

    def origin_for(value)
      return nil if value.blank?

      candidate = value.to_s.strip
      return candidate.chomp("/") if candidate.start_with?("http://", "https://")

      host = hostname_for(candidate)
      host && "https://#{host}"
    end
  end
end

LeonardoPasskeys.configure_from_env!
