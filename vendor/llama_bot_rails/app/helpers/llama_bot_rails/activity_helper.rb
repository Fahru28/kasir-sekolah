module LlamaBotRails
  # Turns activity rows into something an operator can read.
  #
  # §25 of the activity memo: operators see explanations, developers see
  # implementation details. Everything here produces the operator sentence;
  # the technical layer is a separate, permission-gated block in the views.
  #
  # Exposed to host app views (see engine.rb) so any page can drop in
  # `llama_activity_history(record)`.
  module ActivityHelper
    SOURCE_ICONS = {
      "admin_ui" => "fa-user-shield",
      "user_ui" => "fa-user",
      "api" => "fa-code",
      "webhook" => "fa-bolt",
      "background_job" => "fa-gears",
      "rails_callback" => "fa-arrows-turn-right",
      "integration" => "fa-plug",
      "ai_agent" => "fa-robot",
      "system" => "fa-server",
      "console" => "fa-terminal"
    }.freeze

    SOURCE_LABELS = {
      "admin_ui" => "Admin UI",
      "user_ui" => "App",
      "api" => "API",
      "webhook" => "Webhook",
      "background_job" => "Background job",
      "rails_callback" => "Callback",
      "integration" => "Integration",
      "ai_agent" => "Leo",
      "system" => "System",
      "console" => "Console"
    }.freeze

    VERBS = {
      "created" => "created",
      "updated" => "updated",
      "deleted" => "deleted",
      "destroyed" => "deleted",
      "viewed" => "viewed",
      "exported" => "exported",
      "restored" => "restored"
    }.freeze

    # Values that must never be rendered even if some model wrote them into a
    # version. `LlamaBotRails::Auditable` already keeps them out of the table;
    # this catches models using bare has_paper_trail.
    REDACTED = "••••••••".freeze

    def llama_activity_icon(event)
      SOURCE_ICONS.fetch(event.source.to_s, "fa-circle-dot")
    end

    def llama_activity_source_label(event)
      SOURCE_LABELS.fetch(event.source.to_s, event.source.to_s.humanize)
    end

    def llama_activity_actor_name(event)
      return event.actor_label if event.actor_label.present?
      return "System" if event.actor_type == "System"
      return "Leo" if event.source == "ai_agent"

      "Anonymous"
    end

    def llama_activity_subject_name(event)
      return nil if event.subject_type.blank?

      label = event.subject_label.presence
      type = event.subject_type.demodulize.titleize
      label ? "#{type} #{label}" : "#{type} ##{event.subject_id}"
    end

    # The one-line explanation at the top of every row.
    #
    #   "Grace Hopper updated Contact Acme Corp"
    #   "Contact Acme Corp updated automatically"
    def llama_activity_sentence(event)
      verb = llama_activity_verb(event)
      subject = llama_activity_subject_name(event)

      if event.human
        [ llama_activity_actor_name(event), verb, subject ].compact.join(" ")
      elsif subject
        "#{subject} #{verb} automatically"
      else
        "#{event.event_type.tr('.', ' ').humanize} (automatic)"
      end
    end

    # Why an automated change happened, when we know.
    def llama_activity_cause(event)
      return event.trigger_name if event.trigger_name.present?
      return event.job_class if event.job_class.present?
      return "Leo" if event.source == "ai_agent"

      nil
    end

    def llama_activity_verb(event)
      suffix = event.event_type.to_s.split(".").last
      VERBS.fetch(suffix, suffix.to_s.tr("_", " "))
    end

    # --- Time zone -----------------------------------------------------------
    # Every timestamp on these screens is rendered in one named zone (Pacific
    # unless the host app configures otherwise) and the pages say which one, so
    # "2:14 PM" is never a number the reader has to mentally re-base.
    def llama_activity_zone
      LlamaBotRails.display_time_zone
    end

    def llama_activity_zone_label
      LlamaBotRails.display_time_zone_label
    end

    def llama_activity_in_zone(time)
      return nil if time.blank?

      time.in_time_zone(llama_activity_zone)
    end

    def llama_activity_time(time)
      return "—" if time.blank?

      llama_activity_in_zone(time).strftime("%-l:%M %p")
    end

    # Full date + clock, for the pages that show a single event.
    def llama_activity_timestamp(time)
      return "—" if time.blank?

      llama_activity_in_zone(time).strftime("%B %-d, %Y at %-l:%M:%S %p")
    end

    def llama_activity_day(time)
      return "Unknown" if time.blank?

      local = llama_activity_in_zone(time)
      today = llama_activity_zone.today
      case local.to_date
      when today then "Today"
      when today - 1 then "Yesterday"
      else local.strftime("%B %-d, %Y")
      end
    end

    def llama_activity_ago(time)
      return "never" if time.blank?

      "#{time_ago_in_words(time)} ago"
    end

    # [[attribute, from, to], ...] for one version, secrets removed.
    def llama_activity_changes(version)
      changes = version.object_changes
      changes = JSON.parse(changes) if changes.is_a?(String)
      return [] unless changes.is_a?(Hash)

      changes.filter_map do |attribute, (from, to)|
        next if %w[id created_at updated_at].include?(attribute)

        if llama_sensitive_attribute?(attribute)
          [ attribute, REDACTED, REDACTED ]
        else
          [ attribute, from, to ]
        end
      end
    rescue StandardError
      []
    end

    def llama_sensitive_attribute?(attribute)
      configured = LlamaBotRails.config.activity_sensitive_attributes || []
      patterns = LlamaBotRails.config.activity_sensitive_attribute_patterns || []

      configured.include?(attribute.to_s) || patterns.any? { |pattern| attribute.to_s.match?(pattern) }
    end

    def llama_activity_value(value)
      return content_tag(:span, "empty", class: "italic opacity-50") if value.nil? || value == ""
      return content_tag(:span, value ? "yes" : "no") if value == true || value == false

      truncate(value.to_s, length: 120)
    end

    def llama_version_record_name(version)
      "#{version.item_type.demodulize.titleize} ##{version.item_id}"
    end

    # Drop a record's History into any host app view:
    #
    #   <%= llama_activity_history(@contact) %>
    #
    # Renders nothing at all if the viewer is not allowed to see activity, so
    # it is safe to leave in a shared partial.
    def llama_activity_history(record, limit: 25)
      return "".html_safe unless LlamaBotRails::ActivityEvent.available?
      return "".html_safe unless llama_can_view_activity?

      events = LlamaBotRails::ActivityEvent
        .where(subject_type: LlamaBotRails::ActivityEvent.subject_type_for(record), subject_id: record.id.to_s)
        .recent
        .limit(limit)
        .to_a

      render partial: "llama_bot_rails/activity_events/history_timeline",
             locals: { events: events, record: record, versions_by_event: llama_versions_for(events) }
    end

    # Versions for a page of events in one query, keyed by event id.
    def llama_versions_for(events)
      return {} unless defined?(::PaperTrail::Version)

      ids = events.map(&:id)
      return {} if ids.empty?

      ::PaperTrail::Version.where(activity_event_id: ids).order(:id).group_by(&:activity_event_id)
    rescue StandardError
      {}
    end

    def llama_can_view_activity?
      user = LlamaBotRails.current_user_resolver&.call(request.env)
      LlamaBotRails.can?(user, :view_activity)
    rescue StandardError
      false
    end
  end
end
