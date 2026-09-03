require "set"                                 # ← you call Set.new
require "llama_bot_rails/version"
require "llama_bot_rails/engine"
require "llama_bot_rails/llama_bot"
require "llama_bot_rails/agent_state_builder"
require "llama_bot_rails/controller_extensions"
require "llama_bot_rails/agent_auth"
require "llama_bot_rails/error_feed_token"
require "llama_bot_rails/route_helper"
require "llama_bot_rails/scaffold_columns"

module LlamaBotRails
  # ------------------------------------------------------------------
  # Public configuration
  # ------------------------------------------------------------------

  # Allow-list of routes the agent may hit
  mattr_accessor :allowed_routes, default: Set.new

  # Lambda that receives Rack env and returns a user-like object
  class << self
    attr_accessor :user_resolver
    attr_accessor :current_user_resolver
    attr_accessor :sign_in_method

    # Permission system for feedback/requests
    attr_accessor :permission_checker
    attr_accessor :feedback_scope_resolver

    # Unified Login (Phase 3)
    # Lambda that receives a raw grant token and returns [payload, error_code].
    attr_accessor :grant_redeemer
    # Lambda that receives (guid, payload) and returns the host app's User (or nil).
    attr_accessor :guid_user_resolver
    # When true, guid_user_resolver may create-or-link a Devise user from a
    # mothership-VERIFIED grant payload (managed Leo boxes). Default false keeps the
    # conservative "never create, never key by email" behavior for self-hosters.
    attr_accessor :provision_sso_users
  end

  self.provision_sso_users = false
  
  # Default (Devise / Warden); returns nil if Devise absent
  self.user_resolver = ->(user_id) do
    # Try to find a User model, fallback to nil if not found
    # byebug
    if defined?(Devise)
      default_scope = Devise.default_scope # e.g., :user
      user_class = Devise.mappings[default_scope].to
      user_class.find_by(id: user_id)
    else
      Rails.logger.warn("[[LlamaBot]] Implement a user_resolver! in your app to resolve the user from the user_id.")
      nil
    end
  end

  # Default (Devise / Warden); returns nil if Devise absent
  self.current_user_resolver = ->(env) do
    # Try to find a User model, fallback to nil if not found
    if defined?(Devise)
      env['warden']&.user
    else
      Rails.logger.warn("[[LlamaBot]] Implement a current_user_resolver! in your app to resolve the current user from the environment.")
      nil
    end
  end

  # Lambda that receives Rack env and user_id, and sets the user in the warden session
  # Default sign-in method is configured for Devise with Warden.
  self.sign_in_method = ->(env, user) do
    env['warden']&.set_user(user)
  end

  # ------------------------------------------------------------------
  # Unified Login (Phase 3) — GET /llamapress_auth/consume
  # ------------------------------------------------------------------
  # Default redeemer: proxy the grant through LlamaBot (Option 1 — keeps the
  # mothership token out of the Rails container). Returns [payload, error_code].
  self.grant_redeemer = ->(token) do
    LlamaBotRails::LlamaBot.redeem_rails_grant(token)
  end

  # Default guid -> Devise user resolver. Looks the user up by a stable
  # `llamapress_user_guid` column when the host app has one. By default it NEVER
  # keys by email (a grant's email is not proof of ownership of a local account)
  # and never creates — that is the right posture for self-hosters.
  #
  # Managed Leo boxes set `LlamaBotRails.provision_sso_users = true`, which enables
  # lazy claim-on-first-SSO: link by verified email, else provision. That is safe
  # here and only here, because this lambda runs ONLY after `grant_redeemer`
  # succeeds — the payload's email/guid are mothership-verified server-to-server
  # over the bearer channel, not user input. Without it, first-time SSO on the Rails
  # surface dead-ends at "no host user for guid=… — degrading to /" even though the
  # mothership already authorized the person.
  #
  # Host apps that model external identity differently (shadow-user table,
  # first-user provisioning) should override this in an initializer.
  # Returns the User or nil.
  self.guid_user_resolver = ->(guid, payload) do
    return nil if guid.blank?

    unless defined?(Devise)
      Rails.logger.warn("[[LlamaBot]] guid_user_resolver: Devise not loaded — override LlamaBotRails.guid_user_resolver to map a llamapress_user_guid to your app's user.")
      return nil
    end

    user_class = Devise.mappings[Devise.default_scope].to
    unless user_class.column_names.include?("llamapress_user_guid")
      Rails.logger.warn("[[LlamaBot]] guid_user_resolver: #{user_class.name} has no `llamapress_user_guid` column. Add it (unique index) or override LlamaBotRails.guid_user_resolver. Never key by email.")
      return nil
    end

    # 1. Already linked by guid — always wins.
    found = user_class.find_by(llamapress_user_guid: guid)
    return found if found

    return nil unless LlamaBotRails.provision_sso_users

    email = payload && (payload.dig("user", "email") || payload.dig(:user, :email))
    return nil if email.blank?

    # 2. Link an existing Devise user by the mothership-verified email (one-time stamp).
    if (existing = user_class.find_by(email: email))
      existing.update_column(:llamapress_user_guid, guid)
      return existing
    end

    # 3. Provision a fresh SSO-only Devise user (unusable random password).
    begin
      u = user_class.new(email: email, llamapress_user_guid: guid)
      u.password = SecureRandom.hex(32) if u.respond_to?(:password=)
      u.skip_confirmation! if u.respond_to?(:skip_confirmation!)
      u.save!(validate: false)
      u
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
      # Concurrent consume won the race (guid or email unique index). Re-read
      # rather than failing the sign-in.
      Rails.logger.info("[[LlamaBot]] guid_user_resolver: provision raced (#{e.class}); re-reading")
      user_class.find_by(llamapress_user_guid: guid) || user_class.find_by(email: email)
    end
  end

  # ------------------------------------------------------------------
  # Permission system for feedback/requests
  # ------------------------------------------------------------------
  # Default permission checker - allows basic actions, restricts admin actions
  # Client apps can override this in their initializer
  self.permission_checker = ->(user, action, resource_class = nil) do
    # The app has not been locked down yet, so nothing here is restricted —
    # including for a visitor who is not signed in at all. This mirrors the host
    # app's ApplicationController, which ships with authenticate_user! commented
    # out. See config.llama_bot_rails.require_authentication in engine.rb.
    #
    # A host app that assigns its own permission_checker never reaches this line,
    # so the switch can only ever loosen the built-in defaults.
    next true unless LlamaBotRails.require_authentication?

    # Submitting is not per-person, so it is the one action a stranger may reach — and
    # only when the app has explicitly opted in. Checked BEFORE the `unless user` guard
    # below, which every other action still falls through to.
    if (action == :submit_feedback || action == :submit_request) &&
       LlamaBotRails.config.anonymous_feedback_enabled
      next true
    end

    next false unless user

    case action
    when :submit_feedback, :submit_request
      true # Any authenticated user can submit
    when :view_all_feedback, :view_all_requests
      user.respond_to?(:admin?) && user.admin?
    when :manage_tags
      user.respond_to?(:admin?) && user.admin?
    when :moderate_feedback
      user.respond_to?(:admin?) && user.admin?
    when :manage_releases
      user.respond_to?(:admin?) && user.admin?
    when :view_activity, :view_activity_technical
      # Audit data is admin-only in any app that HAS roles. Apps with no
      # `admin?` at all are the single-operator Leo boxes, where the signed-in
      # user is the owner/developer — locking them out of their own activity
      # log would make the feature dead on arrival. Apps with multiple
      # untrusted users must define `admin?` or override this checker.
      user.respond_to?(:admin?) ? user.admin? : true
    when :view_tickets
      # Same shape as :view_activity, and for the same reason. The ticket
      # tracker is an internal engineering surface: the chat UI has always
      # marked its tab data-engineer-only, but the controller itself had no
      # check at all, so the board was readable by anyone who knew the URL.
      # Grouping Tickets into the Inbox tab bar put a link to it in front of
      # every user, which is what made the missing gate worth closing.
      user.respond_to?(:admin?) ? user.admin? : true
    else
      false
    end
  end

  # Scope resolver for filtering records by permission
  # Returns all records for admins, only user's own records for regular users
  self.feedback_scope_resolver = ->(user, resource_class) do
    if user&.respond_to?(:admin?) && user.admin?
      resource_class.all
    else
      resource_class.where(user_id: user&.id)
    end
  end

  # Helper method to check permissions
  def self.can?(user, action, resource_class = nil)
    permission_checker.call(user, action, resource_class)
  end

  # Helper method to get accessible scope for a resource
  def self.accessible_scope(user, resource_class)
    feedback_scope_resolver.call(user, resource_class)
  end

  # Convenience helper for host-app initializers
  def self.config = Rails.application.config.llama_bot_rails

  # Is this app locked down yet? See the long comment on
  # config.llama_bot_rails.require_authentication in engine.rb.
  #
  # Defaults to false (open) and tolerates a missing config so the gem still
  # answers during boot, in a console, or in a host app that predates the
  # setting.
  def self.require_authentication?
    !!config.require_authentication
  rescue StandardError
    false
  end

  # The host app's user model (Devise's default scope), or nil in apps without
  # Devise. Several places used to inline this lookup; activity events resolve
  # an actor_id back to a user through it.
  def self.user_class
    return nil unless defined?(Devise)

    Devise.mappings[Devise.default_scope]&.to
  rescue StandardError
    nil
  end

  # ------------------------------------------------------------------
  # Display time zone
  # ------------------------------------------------------------------
  # Timestamps are stored in UTC. Which zone they were RENDERED in used to be
  # whatever the host app happened to set — the LlamaPress skeleton sets
  # Pacific, but a host that sets nothing rendered UTC, and no screen ever said
  # which of the two you were reading. Now: one resolved zone, named on the page.
  #
  # Order of precedence:
  #   1. config.llama_bot_rails.display_time_zone — explicit, always wins.
  #   2. The host app's config.time_zone, when it has been set to something
  #      other than Rails' own default. Overlay apps (Leonardo and the client
  #      repos) set this in config/application.rb; that setting is the app
  #      owner's answer and outranks ours.
  #   3. Pacific, because that is where this product is operated from.
  #
  # Rails cannot tell "never configured" from "deliberately set to UTC" — both
  # read back as "UTC" — so a bare UTC is treated as unconfigured and falls
  # through to Pacific. An app that genuinely wants UTC sets
  # display_time_zone = "UTC" and gets it.
  DEFAULT_DISPLAY_TIME_ZONE = "Pacific Time (US & Canada)".freeze

  def self.display_time_zone
    configured =
      begin
        config.display_time_zone.presence
      rescue StandardError
        nil
      end
    configured ||= host_app_time_zone
    configured ||= DEFAULT_DISPLAY_TIME_ZONE

    ActiveSupport::TimeZone[configured.to_s] ||
      ActiveSupport::TimeZone[DEFAULT_DISPLAY_TIME_ZONE]
  end

  def self.host_app_time_zone
    zone = Rails.application.config.time_zone
    return nil if zone.blank? || zone.to_s == "UTC"

    zone
  rescue StandardError
    nil
  end
  private_class_method :host_app_time_zone

  # What the screens print, e.g. "Pacific Time (PDT)" or "UTC". Says the zone
  # plainly rather than leaving the reader to guess at an offset.
  def self.display_time_zone_label(zone = display_time_zone)
    name = zone.name.sub(/\s*\(US & Canada\)\z/, "")
    abbreviation = zone.now.strftime("%Z")

    return name if abbreviation.blank? || abbreviation == name || abbreviation.match?(/\A[+-]/)

    "#{name} (#{abbreviation})"
  end

  # The version of the running app/image. Baked into the Docker image at build
  # time from the release git tag (see LlamaPress-Simple Dockerfile/release.yml).
  # Falls back to "dev" for local/source runs.
  def self.app_version
    ENV.fetch("APP_VERSION", "dev")
  end

  # ------------------------------------------------------------------
  # Prompt helpers
  # ------------------------------------------------------------------
  def self.agent_prompt_path  = Rails.root.join("app", "llama_bot", "prompts", "agent_prompt.txt")

  def self.agent_prompt_text
    File.exist?(agent_prompt_path) ? File.read(agent_prompt_path) : "You are LlamaBot, a helpful assistant."
  end

  def self.add_instruction_to_agent_prompt!(str)
    FileUtils.mkdir_p(agent_prompt_path.dirname)
    File.write(agent_prompt_path, "\n#{str}", mode: "a")
  end

  # ------------------------------------------------------------------
  # Bridge to backend service
  # ------------------------------------------------------------------
  def self.send_agent_message(params) = LlamaBot.send_agent_message(params)
end