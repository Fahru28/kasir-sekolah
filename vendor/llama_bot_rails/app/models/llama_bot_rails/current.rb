# frozen_string_literal: true

module LlamaBotRails
  # Per-request / per-job activity context.
  #
  # Everything that wants to know "who is doing this, and as part of which
  # logical operation?" reads from here: the controller concern, the ActiveJob
  # hook, PaperTrail's controller_info, and ActivityEvent.record!.
  #
  # Rails resets every CurrentAttributes subclass around each request and each
  # job (ActiveSupport::CurrentAttributes::Executor), so there is no bleed
  # between requests and none between jobs — including on threaded servers.
  #
  # Nothing in here may raise. A blank context degrades to an event with fewer
  # columns filled in; an exception would take down the host app's request.
  class Current < ActiveSupport::CurrentAttributes
    # Sources that represent a human sitting in front of the application. The
    # adoption metrics (§13 of the activity memo) count ONLY these — a cron job
    # touching 50k rows is not usage.
    HUMAN_SOURCES = %w[admin_ui user_ui].freeze

    # Free-form, but these are the values the base image emits.
    SOURCES = %w[
      admin_ui
      user_ui
      api
      webhook
      background_job
      rails_callback
      integration
      ai_agent
      system
      console
    ].freeze

    attribute :actor            # the ActiveRecord object, when there is one
    attribute :actor_type       # "User", "Agent", "System"
    attribute :actor_id         # string — so "leo" and 42 both fit
    attribute :actor_label      # display name, denormalized for the feed
    attribute :source
    attribute :event_type       # set inside an action to name the event
    attribute :subject          # set inside an action to pin the subject
    attribute :workspace_id
    attribute :request_id
    attribute :correlation_id
    attribute :parent_event_id
    attribute :controller
    attribute :action
    attribute :job_class
    attribute :job_id
    attribute :trigger_type     # "rails_callback", "webhook", ...
    attribute :trigger_name     # "Invoice#recalculate_customer"
    attribute :metadata         # merged into the event's metadata jsonb

    # Correlation ID for the operation in flight, minted on first read.
    #
    # Deliberately NOT taken from an inbound header: a client could then collide
    # (or poison) another operation's correlation group. The controller concern
    # records any inbound value under metadata["upstream_correlation_id"].
    def correlation_id
      super || (self.correlation_id = SecureRandom.uuid)
    end

    def actor=(record)
      super
      return if record.nil?

      self.actor_type ||= record.class.respond_to?(:base_class) ? record.class.base_class.name : record.class.name
      self.actor_id   ||= record.id.to_s
      self.actor_label ||= LlamaBotRails::Current.label_for(record)
    end

    # Did a human cause this? Drives ActivityEvent#human, which every adoption
    # query filters on.
    def human?
      actor_type.to_s == "User" && HUMAN_SOURCES.include?(source.to_s)
    end

    # The subset PaperTrail stamps onto each version it writes, so a version can
    # be traced back to the operation that produced it. Keys must match columns
    # on `versions` or PaperTrail drops them.
    def paper_trail_info
      {
        correlation_id: correlation_id,
        request_id: request_id,
        source: source
      }.compact
    end

    # Attributes shared by every event minted in this context.
    def event_defaults
      {
        actor_type: actor_type,
        actor_id: actor_id,
        actor_label: actor_label,
        workspace_id: workspace_id,
        source: source,
        request_id: request_id,
        correlation_id: correlation_id,
        parent_event_id: parent_event_id,
        controller: controller,
        action: action,
        job_class: job_class,
        job_id: job_id,
        trigger_type: trigger_type,
        trigger_name: trigger_name,
        human: human?
      }
    end

    # Best-effort human label for an actor or subject.
    def self.label_for(record)
      return nil if record.nil?

      %i[display_name full_name name title email].each do |method|
        next unless record.respond_to?(method)

        value = record.public_send(method)
        return value.to_s if value.present?
      end
      "#{record.class.name} ##{record.id}"
    rescue StandardError
      nil
    end
  end
end
