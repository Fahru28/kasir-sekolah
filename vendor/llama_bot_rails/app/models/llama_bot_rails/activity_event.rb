# frozen_string_literal: true

module LlamaBotRails
  # One meaningful thing that happened in the application.
  #
  # PaperTrail answers "what changed on this row?". An ActivityEvent answers
  # "what operation happened, who caused it, and through what interface?" — and
  # it exists even for operations that change no rows at all (a login, a report
  # download, a Leo message).
  #
  # An event may have 0 versions (user viewed a dashboard) or 500 (a CSV
  # import). The link is `correlation_id`, stamped on both sides by
  # LlamaBotRails::Current.
  class ActivityEvent < ApplicationRecord
    self.table_name = "llama_bot_rails_activity_events"

    # Broad buckets, used for retention policy and for the Activity page's
    # filter chips. Derived from event_type's suffix rather than stored, so an
    # app inventing its own event names still lands in a sensible bucket.
    AUDIT_SUFFIXES = %w[created updated deleted destroyed restored].freeze
    PASSIVE_SUFFIXES = %w[viewed searched listed exported].freeze

    validates :event_type, presence: true
    validates :occurred_at, presence: true
    validates :source, presence: true

    belongs_to :parent_event, class_name: "LlamaBotRails::ActivityEvent", optional: true
    has_many :child_events,
             class_name: "LlamaBotRails::ActivityEvent",
             foreign_key: :parent_event_id,
             inverse_of: :parent_event,
             dependent: :nullify

    scope :recent, -> { order(occurred_at: :desc, id: :desc) }
    scope :human, -> { where(human: true) }
    scope :system, -> { where(human: false) }
    scope :by_actor, ->(type, id) { where(actor_type: type.to_s, actor_id: id.to_s) }
    scope :for_subject, ->(record) { where(subject_type: subject_type_for(record), subject_id: record.id.to_s) }
    scope :for_workspace, ->(id) { id.nil? ? all : where(workspace_id: id.to_s) }
    scope :since, ->(time) { where(occurred_at: time..) }
    scope :of_type, ->(*types) { where(event_type: types.flatten.map(&:to_s)) }

    # --- Writing ------------------------------------------------------------

    # The single entry point for recording activity. Safe to call from
    # anywhere — controllers, models, jobs, Leo tools, the console.
    #
    #   LlamaBotRails::ActivityEvent.record!("invoice.approved", subject: invoice)
    #
    # Defaults are pulled from LlamaBotRails::Current, so a caller inside a
    # request or job gets actor/source/correlation for free.
    #
    # NEVER raises: a failure to log activity must not fail the operation being
    # logged. Returns the event, or nil if it could not be written.
    def self.record!(event_type, subject: nil, actor: nil, occurred_at: nil,
                     source: nil, human: nil, metadata: {}, **overrides)
      return nil unless available?

      subject ||= Current.subject
      current = Current.event_defaults

      attrs = current.merge(
        event_type: event_type.to_s,
        occurred_at: occurred_at || Time.current,
        metadata: (Current.metadata || {}).merge(metadata || {}).deep_stringify_keys
      )
      attrs[:source] = source.to_s if source
      attrs.merge!(attributes_for_actor(actor)) if actor
      attrs.merge!(attributes_for_subject(subject)) if subject
      attrs[:source] ||= "system"
      attrs[:human] = human unless human.nil?
      attrs.merge!(overrides)

      event = create!(attrs)
      claim_versions(event)
      event
    rescue StandardError => e
      Rails.logger.warn("[llama_bot_rails] activity event #{event_type} not recorded: #{e.class}: #{e.message}")
      nil
    end

    # Point the versions written earlier in this same operation at the event
    # that explains them.
    #
    # `correlation_id` alone already links the two sides, but the record-level
    # History timeline joins on `activity_event_id` so it can load versions for
    # a page of events in one query. Doing this here (rather than only in the
    # controller) is what makes jobs, callbacks, Leo and console writes show
    # their diffs too. Only claims versions no other event has claimed.
    def self.claim_versions(event)
      return unless defined?(::PaperTrail::Version)
      return if event.correlation_id.blank?

      ::PaperTrail::Version
        .where(correlation_id: event.correlation_id, activity_event_id: nil)
        .update_all(activity_event_id: event.id)
    rescue StandardError
      nil
    end

    # Has the host app installed the migration yet? Apps upgrade the gem before
    # they run `rails llama_bot_rails:install:migrations`, and that window must
    # not 500 every request. Memoized; cleared by the reloader in development.
    def self.available?
      return @available unless @available.nil?

      @available = table_exists?
    rescue StandardError
      false
    end

    def self.reset_availability!
      @available = nil
    end

    # --- Reading ------------------------------------------------------------

    # Every PaperTrail version written during the same logical operation.
    # Correlation-based, so it also picks up versions from callbacks that ran
    # after this event was recorded.
    def versions
      return PaperTrail::Version.none unless defined?(::PaperTrail::Version) && correlation_id.present?

      PaperTrail::Version.where(correlation_id: correlation_id).order(:id)
    end

    def subject
      return nil if subject_type.blank? || subject_id.blank?

      subject_type.constantize.find_by(id: subject_id)
    rescue StandardError
      nil
    end

    def actor
      return nil unless actor_type == "User" && actor_id.present?

      LlamaBotRails.user_class&.find_by(id: actor_id)
    rescue StandardError
      nil
    end

    def category
      suffix = event_type.to_s.split(".").last
      return :audit if AUDIT_SUFFIXES.include?(suffix)
      return :passive if PASSIVE_SUFFIXES.include?(suffix)
      return :system unless human

      :user
    end

    def self.subject_type_for(record)
      klass = record.is_a?(Class) ? record : record.class
      klass.respond_to?(:base_class) ? klass.base_class.name : klass.name
    end

    def self.attributes_for_subject(record)
      {
        subject_type: subject_type_for(record),
        subject_id: record.id.to_s,
        subject_label: Current.label_for(record)
      }
    end
    private_class_method :attributes_for_subject

    def self.attributes_for_actor(record)
      return { actor_type: "System", actor_id: nil, actor_label: record.to_s } if record.is_a?(String) || record.is_a?(Symbol)

      {
        actor_type: subject_type_for(record),
        actor_id: record.id.to_s,
        actor_label: Current.label_for(record)
      }
    end
    private_class_method :attributes_for_actor
  end
end
