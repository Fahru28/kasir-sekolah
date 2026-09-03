module LlamaBotRails
  require "llama_bot_rails/agent_state_builder"

  class Engine < ::Rails::Engine
    isolate_namespace LlamaBotRails

    # COMMENTED OUT 2026-02-12: Auto-loading migrations causes PG::DuplicateTable errors
    # in downstream forks (e.g., apps forked from Leonardo).
    #
    # Root cause: When apps run `rails llama_bot_rails:install:migrations`, the migrations
    # are copied to db/migrate/ with new timestamps. This auto-loader then appends the
    # engine's original migrations (with different timestamps) to the migration paths,
    # causing Rails to see BOTH sets as separate migrations and try to run both.
    #
    # Fix: Host apps should use `rails llama_bot_rails:install:migrations` to copy
    # migrations explicitly. Rails tracks these with a comment like:
    #   # This migration comes from llama_bot_rails (originally 20260125000000)
    #
    # See: https://guides.rubyonrails.org/engines.html#migrations
    #
    # Original code (kept for reference):
    # initializer "llama_bot_rails.append_migrations" do |app|
    #   unless app.root.to_s.match?(root.to_s)
    #     config.paths["db/migrate"].expanded.each do |expanded_path|
    #       app.config.paths["db/migrate"] << expanded_path
    #     end
    #   end
    # end

    config.generators do |g|
      g.test_framework :rspec
      g.fixture_replacement :factory_bot
      g.factory_bot dir: "spec/factories"
    end

    config.llama_bot_rails = ActiveSupport::OrderedOptions.new

    config.llama_bot_rails.websocket_url = "ws://llamabot-backend:8000/ws"
    config.llama_bot_rails.llamabot_api_url ="http://llamabot-backend:8000"
    config.llama_bot_rails.enable_console_tool = true
    config.llama_bot_rails.verbose_logging = false

    # --- Feedback email notifications (opt-in) ---------------------------------
    # When enabled, the host app emails its managers on new feedback and emails
    # users when there is new activity (comment/mention/status change) on their
    # feedback. SMTP itself is configured in the host app (ActionMailer); the gem
    # only enqueues mail. Disabled by default so apps without SMTP are unaffected.
    config.llama_bot_rails.feedback_email_enabled = false
    config.llama_bot_rails.feedback_notification_emails = []
    config.llama_bot_rails.feedback_email_from = "feedback@llamapress.ai"
    # Host (e.g. 'app.example.com') used to build absolute links in emails.
    # Leave nil to omit links.
    config.llama_bot_rails.feedback_email_url_host = nil

    # --- Release / version-notes email (opt-in) --------------------------------
    # When an admin clicks "Email this release", the host app emails the
    # configured recipient list about the new version. SMTP itself is configured
    # in the host app (ActionMailer); the gem only enqueues mail. Disabled by
    # default so apps without SMTP are unaffected.
    config.llama_bot_rails.release_email_enabled = false
    config.llama_bot_rails.release_notification_emails = []
    config.llama_bot_rails.release_email_from = "releases@llamapress.ai"
    # Host (e.g. 'app.example.com') used to build absolute links in release
    # emails. Leave nil to omit links.
    config.llama_bot_rails.release_email_url_host = nil

    # --- Access control --------------------------------------------------------
    # Off by default, mirroring the host app's ApplicationController, which ships
    # with `before_action :authenticate_user!` commented out. A brand-new Leo box
    # usually has no admin and often no users at all, so gating these screens on
    # sign-in or on `admin?` would make them dead on arrival: the owner opens the
    # Activity tab and is told they do not have access to their own audit log.
    #
    # While this is false:
    #   - require_authentication! does not redirect, so screens that do not need
    #     to know who you are (Activity, Releases) render for anyone.
    #   - the DEFAULT permission checker allows every action, so admin-only
    #     screens open up too.
    #
    # Set it to true when the app is locked down, in the same edit where the host
    # app uncomments `before_action :authenticate_user!`:
    #
    #   # config/initializers/llama_bot_rails.rb
    #   Rails.application.config.llama_bot_rails.require_authentication = true
    #
    # Two things this switch deliberately does NOT do:
    #   - It never overrides a host app that supplies its own permission_checker.
    #     Only the built-in checker consults it.
    #   - It cannot open screens that are per-person by nature (Messages,
    #     Notifications, and READING feedback). Those call require_llama_user!, which
    #     always needs a signed-in user, because there is no honest way to show "your
    #     inbox" to someone whose identity is unknown.
    #
    #     SUBMITTING feedback is the exception, and it is a separate switch. The bubble
    #     does two jobs in one panel: reading an inbox, which is per-person, and sending
    #     a message, which is not. A stranger can do the second honestly. See
    #     config.llama_bot_rails.anonymous_feedback_enabled below.
    config.llama_bot_rails.require_authentication = false

    # --- Activity / audit ------------------------------------------------------
    # Every request and job gets an activity context (LlamaBotRails::Current),
    # PaperTrail versions get stamped with it, and meaningful requests become
    # ActivityEvent rows. See docs/activity_events.md.
    #
    # Lives in the ENGINE, not the base image's app/, because client overlays
    # volume-mount over app/ — anything there would vanish downstream.
    config.llama_bot_rails.activity_tracking_enabled = true
    # Page views are the bulk of the write volume and the least of the value;
    # apps that want them flip this on and pay for the retention.
    config.llama_bot_rails.activity_track_get_requests = false
    # How the controller concern finds the human behind the request.
    config.llama_bot_rails.activity_actor_method = :current_user
    # Callable, receives the controller, returns the tenant id. LlamaPress apps
    # are one-app-per-instance today, so nil by default.
    config.llama_bot_rails.activity_workspace_resolver = nil
    # Never written into a version, even for audited models.
    config.llama_bot_rails.activity_sensitive_attributes = %w[
      password password_digest encrypted_password
      reset_password_token confirmation_token unlock_token invitation_token
      otp_secret otp_backup_codes
      api_key secret_key access_token refresh_token
    ]
    config.llama_bot_rails.activity_sensitive_attribute_patterns = [
      /_token\z/, /_secret\z/, /\Aencrypted_/, /password/
    ]
    # Changing only these does not create a version.
    config.llama_bot_rails.activity_ignored_attributes = %w[]

    # --- Display time zone -----------------------------------------------------
    # The zone every gem-rendered timestamp is shown in, and named on the page.
    # nil = follow the host app's config.time_zone if it sets one, else Pacific.
    # See LlamaBotRails.display_time_zone for the full precedence rule.
    config.llama_bot_rails.display_time_zone = nil

    # --- Page config injection -------------------------------------------------
    # `window.llamapressConfig` is written into every HTML page by an
    # after_action (LlamaBotRails::PageConfigInjection) instead of by a layout
    # partial, so a layout that nobody remembered to wire up cannot silently
    # turn the feedback bubble off. Kill switch for hosts that want to keep
    # owning it in their own layout:
    #
    #   config.llama_bot_rails.inject_page_config = false
    config.llama_bot_rails.inject_page_config = true
    # Read by the injected config; the bubble also requires a signed-in user.
    config.llama_bot_rails.feedback_bubble_enabled = true

    # Let signed-out visitors SUBMIT feedback. Reading stays shut — see the
    # require_authentication comment above for why those two are not the same thing.
    #
    # Default off, so no existing app changes behaviour on upgrade. An app owner opts in
    # from config/initializers/llama_bot_rails.rb, which is on Leonardo's writable list.
    #
    # This value is read at BOOT, so flipping it needs a container restart, not just a
    # file save.
    #
    # Opening this endpoint to strangers brings three defences with it, all in
    # UserFeedbacksController: a signed submission token issued with the page, a honeypot
    # field, and a rate limit. Attachments are stripped from signed-out submissions.
    config.llama_bot_rails.anonymous_feedback_enabled = false

    initializer "llama_bot_rails.page_config_injection" do
      # Config is read INSIDE the load hook, not here: engine initializers run
      # before the host's config/initializers, so a host that disables this
      # there would otherwise be ignored.
      ActiveSupport.on_load(:action_controller_base) do
        include LlamaBotRails::PageConfigInjection if LlamaBotRails.config.inject_page_config
      end
    end

    initializer "llama_bot_rails.activity_tracking" do |app|
      require "llama_bot_rails/job_activity_tracking"

      # Config is read INSIDE the load hooks, not here: engine initializers run
      # before the host's config/initializers, so a host that disables tracking
      # there would otherwise be ignored.
      ActiveSupport.on_load(:action_controller_base) do
        include LlamaBotRails::ActivityTracking if LlamaBotRails.config.activity_tracking_enabled
      end

      ActiveSupport.on_load(:active_job) do
        include LlamaBotRails::JobActivityTracking if LlamaBotRails.config.activity_tracking_enabled
      end

      # The "is the table there yet?" answer is memoized; a reload (or a
      # migration run in the same process) must be able to invalidate it.
      app.config.to_prepare do
        LlamaBotRails::ActivityEvent.reset_availability! if defined?(LlamaBotRails::ActivityEvent)
      end
    end

    # --- Error telemetry to the mothership -------------------------------------
    # Auto-on for managed Leo boxes (detected by the MOTHERSHIP_* env vars) and
    # silently off everywhere else. Kill switch: LLAMA_BOT_ERROR_TELEMETRY=false.
    # Set async false only in tests — it makes delivery block the request.
    config.llama_bot_rails.error_telemetry_async = true

    initializer "llama_bot_rails.assets.precompile" do |app|
      app.config.assets.precompile += %w[
        llama_bot_rails/application.js
        llama_bot_rails/controllers/record_drawer_controller.js
        llama_bot_rails/controllers/filter_panel_controller.js
        llama_bot_rails/scaffold.css
      ]
    end

    # LlamaPress scaffold templates: plain `bin/rails generate scaffold ...`
    # in host apps produces a filterable table index + Turbo detail drawer
    # (docs/scaffold_templates.md). Appended (not unshifted) so a host's own
    # lib/templates overrides — which Rails puts first — always win.
    # Escape hatch: LLAMAPRESS_SCAFFOLD=plain restores stock Rails scaffolds.
    initializer "llama_bot_rails.scaffold_templates" do |app|
      unless ENV["LLAMAPRESS_SCAFFOLD"] == "plain"
        app.config.generators.templates << Engine.root.join("lib/llama_bot_rails/scaffold_templates").to_s
      end
      app.config.generators.view_specs false
    end

    # Serve the drawer/filter Stimulus controllers through the host importmap
    # under the "controllers/" namespace, so the standard
    # eagerLoadControllersFrom("controllers", ...) registers them with no host
    # JS edits. Guarded: hosts without importmap-rails are unaffected.
    initializer "llama_bot_rails.importmap", before: "importmap" do |app|
      if app.config.respond_to?(:importmap)
        app.config.importmap.paths << Engine.root.join("config/importmap.rb")
        app.config.importmap.cache_sweepers << Engine.root.join("app/assets/javascripts")
      end
    end

    # Expose llama_record_frame (drawer frame wrapper) and the activity
    # formatting helpers — the latter so any host view can drop in
    # `llama_activity_history(record)` for a record's History tab.
    initializer "llama_bot_rails.scaffold_helper" do
      ActiveSupport.on_load(:action_controller_base) do
        helper LlamaBotRails::ScaffoldHelper
        helper LlamaBotRails::ActivityHelper
        helper LlamaBotRails::PaginationHelper
      end
    end

    # --- Pagination ------------------------------------------------------------
    # Every list page gets the same styled nav. Hosts that want Pagy's own markup
    # back set this to false.
    config.llama_bot_rails.styled_pagy_nav = true

    # Prepend (not a helper override): apps include Pagy::Frontend in their own
    # ApplicationHelper, which is mixed in AFTER the engine's helpers, so a plain
    # helper method of the same name would lose. Prepending onto Pagy::Frontend
    # itself wins wherever it is included.
    initializer "llama_bot_rails.styled_pagy_nav" do
      require "llama_bot_rails/pagy_nav_override"

      ActiveSupport.on_load(:action_view) do
        if defined?(::Pagy::Frontend) && LlamaBotRails.config.styled_pagy_nav
          ::Pagy::Frontend.prepend(LlamaBotRails::PagyNavOverride)
        end
      end
    end

    initializer "llama_bot_rails.defaults" do |app|
      app.config.llama_bot_rails.state_builder_class ||= "LlamaBotRails::AgentStateBuilder"
    end

    initializer "llama_bot_rails.message_verifier" do |app|
      # Ensure the message verifier is available
      Rails.application.message_verifier(:llamabot_ws)
    end

    # Unified Login (Phase 3): serve GET /llamapress_auth/consume at the HOST
    # app root (NOT under the engine's /llama_bot mount) — the frozen Phase 2
    # frontend sets the iframe src to `{railsUrl}/llamapress_auth/consume`.
    # Prepending onto the host's routes means every downstream app/fork gets it
    # automatically with zero routes.rb edits. It only ADDS a route; behavior
    # with no token is unchanged. See UnifiedLoginController.
    initializer "llama_bot_rails.unified_login_route" do |app|
      app.routes.prepend do
        get "/llamapress_auth/consume",
            to: "llama_bot_rails/unified_login#consume",
            as: :llamapress_auth_consume
      end
    end

    # Rails-side error telemetry: report unhandled exceptions to the mothership
    # so a Rails crash on a Leo box lands on /admin/instance_errors alongside
    # the ones LlamaBot already reports. See docs/error_telemetry.md.
    #
    # INSERTED AFTER DebugExceptions, deliberately — "after" in a Rack stack
    # means INSIDE, so this wraps everything below it: the router and the app,
    # plus ActionableExceptions, Reloader and Migration::CheckPending (which is
    # what makes ActiveRecord::PendingMigrationError visible). Inserting higher
    # — e.g. after ActionDispatch::Executor — would put us OUTSIDE
    # ShowExceptions/DebugExceptions, both of which render an error page
    # without re-raising whenever show_exceptions is :all. Every Leo box runs
    # RAILS_ENV=development, where it is :all, so a middleware up there would
    # never see a single application exception.
    # Periodic "do my blob rows still have files?" check (mothership SI#327). Nothing in
    # the fleet compared active_storage_blobs against disk, so seven boxes lost 481
    # attachments unnoticed — one for three months — while backup health stayed green.
    #
    # A plain thread rather than a job queue: this must work on every box, and the fleet
    # has no recurring-job infrastructure to depend on. Each Puma worker starts one, so a
    # multi-worker box reports more than once; the receiver dedups per
    # (instance, fingerprint) in a 10-minute window and the fingerprint here is stable per
    # box+root, so those collapse into one row rather than spamming.
    initializer "llama_bot_rails.storage_integrity" do |app|
      require "llama_bot_rails/storage_integrity"

      app.config.after_initialize do
        next if ENV["LLAMA_BOT_STORAGE_INTEGRITY"].to_s.strip.downcase == "false"
        next unless LlamaBotRails::MothershipReporter.enabled?
        next if defined?(Rails::Console) || Rails.env.test?

        Thread.new do
          Thread.current.name = "llama_bot_rails.storage_integrity"
          # Let boot finish first, and jitter so the fleet does not arrive at once.
          sleep(300 + rand(600))
          loop do
            begin
              LlamaBotRails::StorageIntegrity.report!
            rescue Exception # rubocop:disable Lint/RescueException
              # A durability check must never take down the app it is checking.
              nil
            end
            # Slow-moving failure; once every ~12h (jittered) is plenty.
            sleep(12 * 3600 + rand(3600))
          end
        end
      end
    end

    initializer "llama_bot_rails.error_telemetry" do |app|
      require "llama_bot_rails/mothership_reporter"
      require "llama_bot_rails/error_telemetry_middleware"
      require "llama_bot_rails/error_subscriber"

      LlamaBotRails::MothershipReporter.async = app.config.llama_bot_rails.error_telemetry_async

      if defined?(ActionDispatch::DebugExceptions)
        app.config.middleware.insert_after ActionDispatch::DebugExceptions,
                                           LlamaBotRails::ErrorTelemetryMiddleware
      else
        # Unusual stack (API-only variants, custom builds). Still report; we
        # just catch less.
        app.config.middleware.use LlamaBotRails::ErrorTelemetryMiddleware
      end

      # Catches what never reaches the Rack stack: jobs, async queries, and
      # anything the host app hands to Rails.error. Deferred to after_initialize
      # so a host app's own subscribers are already in place.
      app.config.after_initialize do
        if Rails.respond_to?(:error) && Rails.error.respond_to?(:subscribe)
          Rails.error.subscribe(LlamaBotRails::ErrorSubscriber.new)
        end
      end
    end
  end
end
