# frozen_string_literal: true

module LlamaBotRails
  # Populates LlamaBotRails::Current for the request, hands the same context to
  # PaperTrail, and records one ActivityEvent per meaningful request.
  #
  # Auto-included into ActionController::Base by the engine, so every app built
  # on the base image gets it without editing its own ApplicationController
  # (client overlays replace app/, so an ApplicationController edit would not
  # survive anyway). Opt out per controller:
  #
  #   skip_llama_activity_tracking            # whole controller
  #   skip_llama_activity_tracking only: :ping
  #
  # Every hook is wrapped so that a failure here can never fail the request the
  # host app is actually trying to serve.
  module ActivityTracking
    extend ActiveSupport::Concern

    # Actions whose default event name reads better as a past-tense verb.
    ACTION_VERBS = {
      "create" => "created",
      "update" => "updated",
      "destroy" => "deleted",
      "delete" => "deleted"
    }.freeze

    # Devise `current_<scope>` helpers run Warden strategies, which is unsafe from
    # a before_action that may precede CSRF verification. For these we read warden
    # directly; anything else is a host-supplied method we call as given.
    LLAMA_PASSIVE_ACTOR_METHODS = %i[
      current_user current_admin current_account current_member
    ].freeze

    included do
      class_attribute :llama_activity_tracking_enabled, instance_writer: false, default: true
      class_attribute :llama_activity_event_name, instance_writer: false, default: nil

      before_action :llama_begin_activity_context
      after_action :llama_record_activity_event
    end

    class_methods do
      def skip_llama_activity_tracking(**options)
        skip_before_action :llama_begin_activity_context, **options, raise: false
        skip_after_action :llama_record_activity_event, **options, raise: false
        self.llama_activity_tracking_enabled = false if options.empty?
      end

      # Name the event this controller records, instead of the derived
      # "<resource>.<verb>". Also settable per-action with
      # `LlamaBotRails::Current.event_type = "invoice.approved"`.
      def llama_activity_event(name)
        self.llama_activity_event_name = name.to_s
      end
    end

    # PaperTrail's own before_action assigns
    # `PaperTrail.request.controller_info = info_for_paper_trail` and runs after
    # ours, so setting controller_info directly is not enough — this override is
    # what actually gets the correlation onto each version.
    #
    # An app that defines its own info_for_paper_trail in ApplicationController
    # overrides this one (a subclass always beats a module included into
    # ActionController::Base): call `super` there to keep correlation working.
    def info_for_paper_trail
      base = defined?(super) ? (super || {}) : {}
      return base unless llama_activity_tracking?

      base.merge(LlamaBotRails::Current.paper_trail_info)
    rescue StandardError
      {}
    end

    private

    def llama_begin_activity_context
      return unless llama_activity_tracking?

      current = LlamaBotRails::Current
      current.source ||= llama_activity_source
      current.request_id ||= request.request_id
      current.controller = controller_path
      current.action = action_name
      # No actor for anonymous traffic: actor_type stays nil (the feed renders
      # it as "Anonymous") rather than claiming "System", which would make a
      # public form submission look machine-generated.
      current.actor ||= llama_activity_actor
      current.workspace_id ||= llama_activity_workspace_id
      current.metadata = (current.metadata || {}).merge(llama_activity_request_metadata)

      llama_configure_paper_trail
    rescue StandardError => e
      llama_activity_warn(e, "context")
    end

    def llama_record_activity_event
      return unless llama_activity_tracking?
      return unless llama_activity_worth_recording?

      versions = llama_activity_versions
      subject = LlamaBotRails::Current.subject || llama_activity_subject_from(versions)

      # record! links the versions written during this request to the event
      # (ActivityEvent.claim_versions), so there is nothing to do afterwards.
      LlamaBotRails::ActivityEvent.record!(
        llama_activity_event_type,
        subject: subject,
        changed_records_count: versions.size,
        metadata: { "status" => response.status }
      )
    rescue StandardError => e
      llama_activity_warn(e, "record")
    end

    def llama_activity_tracking?
      llama_activity_tracking_enabled && LlamaBotRails.config.activity_tracking_enabled
    end

    # Only successful requests become events; a 422 from a failed validation
    # changed nothing worth telling an administrator about.
    def llama_activity_worth_recording?
      return false unless response.status < 400

      llama_activity_mutating_request? || LlamaBotRails.config.activity_track_get_requests ||
        LlamaBotRails::Current.event_type.present?
    end

    def llama_activity_mutating_request?
      !request.get? && !request.head?
    end

    # Versions written during THIS operation. Correlation-based, so callbacks
    # and nested saves are included without any bookkeeping in the models.
    def llama_activity_versions
      return [] unless defined?(::PaperTrail::Version)
      return [] unless ::PaperTrail::Version.table_exists?

      ::PaperTrail::Version
        .where(correlation_id: LlamaBotRails::Current.correlation_id)
        .order(:id)
        .pluck(:item_type, :item_id)
    rescue StandardError
      []
    end

    # The record the operation was about: the first thing it changed.
    def llama_activity_subject_from(versions)
      item_type, item_id = versions.first
      return nil if item_type.blank?

      item_type.constantize.find_by(id: item_id)
    rescue StandardError
      nil
    end

    def llama_activity_event_type
      return LlamaBotRails::Current.event_type if LlamaBotRails::Current.event_type.present?
      return self.class.llama_activity_event_name if self.class.llama_activity_event_name.present?

      resource = controller_path.tr("/", ".").singularize
      verb = ACTION_VERBS.fetch(action_name, action_name)
      "#{resource}.#{verb}"
    end

    # Engine controllers are the admin surface; everything else is the app's
    # own UI. JSON requests without a session are API traffic.
    def llama_activity_source
      return "admin_ui" if controller_path.start_with?("llama_bot_rails/")
      return "api" if request.format.json? && !llama_activity_actor

      "user_ui"
    end

    # Resolving the actor must never RUN authentication. This concern is included
    # into ActionController::Base, so its before_action can land ahead of an app's
    # verify_authenticity_token. Calling `current_user` there makes Warden
    # authenticate straight from the POST /users/sign_in params, and Devise's
    # clean_up_csrf_token_on_authentication then deletes session[:_csrf_token]
    # before it is ever checked -- the correct password gets rejected and the user
    # can never sign in (mothership SupportIncident #187, leo-mezuli 2026-08-21).
    # So read the already-authenticated user passively instead.
    def llama_activity_actor
      method = LlamaBotRails.config.activity_actor_method
      return nil unless method && respond_to?(method, true)

      warden = request.env["warden"] if respond_to?(:request, true) && request
      if warden && LLAMA_PASSIVE_ACTOR_METHODS.include?(method.to_sym)
        # nil unless the user is ALREADY signed in; never runs a strategy.
        warden.user(llama_activity_warden_scope(method))
      else
        send(method)
      end
    rescue StandardError
      nil
    end

    # :current_user -> :user, :current_admin -> :admin. Devise names its warden
    # scopes after the model, and its helpers after the scope.
    def llama_activity_warden_scope(method)
      method.to_s.delete_prefix("current_").to_sym
    end

    def llama_activity_workspace_id
      resolver = LlamaBotRails.config.activity_workspace_resolver
      return nil unless resolver.respond_to?(:call)

      resolver.call(self)&.to_s
    rescue StandardError
      nil
    end

    # Request params are deliberately NOT captured: they are the most likely
    # place for a password or a token to leak into the audit log.
    def llama_activity_request_metadata
      metadata = {
        "method" => request.request_method,
        "path" => request.path,
        "ip" => request.remote_ip
      }
      upstream = request.headers["X-Correlation-Id"].presence
      metadata["upstream_correlation_id"] = upstream if upstream
      metadata
    end

    def llama_configure_paper_trail
      return unless defined?(::PaperTrail) && ::PaperTrail.respond_to?(:request)

      ::PaperTrail.request.whodunnit = LlamaBotRails::Current.actor_id
      ::PaperTrail.request.controller_info = LlamaBotRails::Current.paper_trail_info
    end

    def llama_activity_warn(error, phase)
      Rails.logger.warn(
        "[llama_bot_rails] activity tracking (#{phase}) failed in " \
        "#{controller_path}##{action_name}: #{error.class}: #{error.message}"
      )
    end
  end
end
