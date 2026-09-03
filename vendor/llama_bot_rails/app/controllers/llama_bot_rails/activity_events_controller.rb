module LlamaBotRails
  # The Activity / History / Usage admin surface (phase 2 of the activity memo).
  #
  # Three views over the same table:
  #   index   — application-wide chronological feed, filterable
  #   show    — one operation: actor, source, and every record it changed
  #   usage   — human adoption: active users, meaningful actions, workflows
  #   history — everything that ever happened to one record
  #
  # Read-only by design. Nothing here can mutate application data.
  class ActivityEventsController < ApplicationController
    include Authorizable
    include ScaffoldFiltering

    layout false

    before_action :require_authentication!
    before_action :require_activity_access!
    before_action :require_installed!
    # Wraps the whole action, so the From/To date filters, the day grouping and
    # every rendered clock agree on one zone instead of quietly using UTC.
    around_action :use_display_time_zone

    SEARCH_COLUMNS = %i[event_type actor_label subject_label].freeze

    def index
      @pagy, @events = llama_paginate(filtered_events.recent)
      @event_types = ActivityEvent.distinct.order(:event_type).limit(200).pluck(:event_type)
      @sources = ActivityEvent.distinct.order(:source).pluck(:source).compact
      @actors = actor_options
      @selected_actor = params[:actor_id].presence
      @selected_actor_label = @actors.find { |_label, id| id == @selected_actor }&.first
    end

    def show
      @event = ActivityEvent.find(params[:id])
      @versions = @event.versions.to_a
      @children = @event.child_events.recent.limit(25).to_a
    end

    # Record-level history. Subject type/id come from the URL, so the type is
    # checked against the types actually present in the table rather than
    # constantized straight from user input.
    def history
      @subject_type = known_subject_type(params[:subject_type])
      @subject_id = params[:subject_id].to_s

      unless @subject_type
        redirect_to activity_path, alert: "Unknown record type." and return
      end

      @events = ActivityEvent
        .where(subject_type: @subject_type, subject_id: @subject_id)
        .recent
      @pagy, @events = llama_paginate(@events)
      @subject_label = @events.first&.subject_label
      @versions_by_event = versions_for(@events)
    end

    def usage
      now = Time.current
      human = ActivityEvent.human

      @window = { now: now }
      @metrics = {
        actions_7d: human.since(now - 7.days).count,
        actions_30d: human.since(now - 30.days).count,
        actions_prev_30d: human.where(occurred_at: (now - 60.days)...(now - 30.days)).count,
        active_today: distinct_actors(human.since(now.beginning_of_day)),
        active_7d: distinct_actors(human.since(now - 7.days)),
        active_30d: distinct_actors(human.since(now - 30.days)),
        active_days_14: human.since(now - 14.days).group(Arel.sql("DATE(occurred_at)")).count.size,
        last_activity: human.maximum(:occurred_at),
        total_events: ActivityEvent.count,
        system_events_30d: ActivityEvent.system.since(now - 30.days).count
      }

      @workflows = human.since(now - 30.days)
        .group(:event_type)
        .order(Arel.sql("COUNT(*) DESC"))
        .limit(10)
        .count

      @users = user_rows(now)
    end

    private

    def use_display_time_zone(&block)
      @display_time_zone = LlamaBotRails.display_time_zone
      Time.use_zone(@display_time_zone, &block)
    end

    # Everyone who has ever shown up as an actor, for the "Person" filter.
    # Built from the events themselves rather than the user table: those are
    # exactly the people the filter can return rows for, and it also covers
    # actors that are not host-app users (Leo, a system component).
    #
    # actor_label is denormalized onto every event, so someone who changed their
    # name has several. Take the label off each actor's most recent event —
    # two bounded queries, not one per person.
    def actor_options
      newest = ActivityEvent.where.not(actor_id: nil).group(:actor_id).maximum(:id)
      return [] if newest.empty?

      ActivityEvent
        .where(id: newest.values)
        .pluck(:actor_id, :actor_label)
        .map { |id, label| [ label.presence || "User ##{id}", id.to_s ] }
        .sort_by { |label, _id| label.downcase }
        .first(200)
    end

    def filtered_events
      scope = llama_filtered_scope(ActivityEvent.all,
                                   search_columns: SEARCH_COLUMNS,
                                   date_column: :occurred_at)

      scope = scope.where(event_type: params[:event_type]) if params[:event_type].present?
      scope = scope.where(source: params[:source]) if params[:source].present?
      scope = scope.where(actor_id: params[:actor_id].to_s) if params[:actor_id].present?
      scope = scope.where(subject_type: params[:subject_type]) if params[:subject_type].present?

      case params[:category]
      when "human" then scope.human
      when "system" then scope.system
      else scope
      end
    end

    # Versions for a page of events, in one query, keyed by event id — the feed
    # would otherwise fire one query per row.
    def versions_for(events)
      return {} unless defined?(::PaperTrail::Version)

      ids = events.map(&:id)
      return {} if ids.empty?

      ::PaperTrail::Version.where(activity_event_id: ids).order(:id).group_by(&:activity_event_id)
    rescue StandardError
      {}
    end

    def distinct_actors(scope)
      scope.where.not(actor_id: nil).distinct.count(:actor_id)
    end

    # One row per user of the app, whether or not they have ever done anything —
    # "never activated" is the most important row on the page.
    def user_rows(now)
      human = ActivityEvent.human
      actions_7d = human.since(now - 7.days).group(:actor_id).count
      actions_30d = human.since(now - 30.days).group(:actor_id).count
      last_seen = human.group(:actor_id).maximum(:occurred_at)

      users = LlamaBotRails.user_class&.order(:id)&.limit(200)&.to_a || []
      users.map do |user|
        key = user.id.to_s
        {
          user: user,
          label: LlamaBotRails::Current.label_for(user),
          actions_7d: actions_7d[key].to_i,
          actions_30d: actions_30d[key].to_i,
          last_active: last_seen[key]
        }
      end.sort_by { |row| [ -row[:actions_7d], -(row[:last_active]&.to_i || 0) ] }
    end

    def known_subject_type(value)
      return nil if value.blank?

      ActivityEvent.where(subject_type: value).exists? ? value : nil
    end

    def require_activity_access!
      return if can?(:view_activity)

      respond_to do |format|
        format.html { redirect_to llama_bot_rails.unauthorized_path }
        format.json { render json: { error: "Unauthorized" }, status: :forbidden }
      end
    end

    # The gem can be newer than the app's schema; say so instead of 500ing.
    def require_installed!
      return if ActivityEvent.available?

      render plain: "Activity tracking is not installed yet. Run: " \
                    "bin/rails llama_bot_rails:install:migrations && bin/rails db:migrate",
             status: :service_unavailable
    end
  end
end
