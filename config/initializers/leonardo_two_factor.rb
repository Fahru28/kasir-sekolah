# frozen_string_literal: true

# Reusable configuration layer for optional two-factor authentication.
#
# 2FA is OFF by default. A project turns it on by setting TWO_FACTOR_ENABLED=true
# and including TwoFactorAuthenticatableUser in its User model (see
# app/models/concerns/two_factor_authenticatable_user.rb). Each end user then
# enrolls individually -- until they do, login works exactly like plain Devise.
module LeonardoTwoFactor
  # Label shown in the user's authenticator app (Google Authenticator, 1Password...).
  mattr_accessor :issuer
  self.issuer = ENV.fetch("TWO_FACTOR_ISSUER", "Leonardo")

  # Master switch. Gate the 2FA enrollment UI on this so a project can ship the
  # capability dark and flip it on per environment.
  mattr_accessor :enabled
  self.enabled = ActiveModel::Type::Boolean.new.cast(
    ENV.fetch("TWO_FACTOR_ENABLED", "false")
  )

  def self.enabled?
    enabled
  end
end

# devise-two-factor 6.x stores the OTP secret with Active Record Encryption, so
# encryption keys must be configured before any secret is written. We wire them
# from ENV when provided (so opt-in projects never have to patch the base image).
#
# In non-production environments we fall back to stable keys derived from
# secret_key_base, so the enrollment flow works out of the box locally and in CI.
# In production we leave encryption untouched when keys are absent: with 2FA off
# no secret is ever written, so the app boots fine -- and a project enabling 2FA
# is forced to supply real keys rather than silently relying on a derived one.
if ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].present?
  ActiveRecord::Encryption.configure(
    primary_key:         ENV.fetch("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"),
    deterministic_key:   ENV.fetch("ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"),
    key_derivation_salt: ENV.fetch("ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT")
  )
elsif !Rails.env.production?
  secret = Rails.application.secret_key_base.to_s
  ActiveRecord::Encryption.configure(
    primary_key:         Digest::SHA256.hexdigest("leonardo-2fa-primary-#{secret}"),
    deterministic_key:   Digest::SHA256.hexdigest("leonardo-2fa-deterministic-#{secret}"),
    key_derivation_salt: Digest::SHA256.hexdigest("leonardo-2fa-salt-#{secret}")
  )
end
