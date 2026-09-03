# frozen_string_literal: true

module LlamaBotRails
  # Standard audit configuration for a model:
  #
  #   class Order < ApplicationRecord
  #     include LlamaBotRails::Auditable
  #   end
  #
  # Gives you PaperTrail versioning with the base image's sensitive-field
  # policy applied, plus `order.activity_events` for the record's History tab.
  #
  # Options pass straight through to has_paper_trail, so an app can narrow it:
  #
  #   include LlamaBotRails::Auditable
  #   audit_only :status, :total   # nothing else creates a version
  #
  # Degrades to a no-op (rather than raising) when paper_trail is absent, so
  # including it can never break an app's boot.
  module Auditable
    extend ActiveSupport::Concern

    # Stamped onto every version this model writes, from the ambient activity
    # context.
    #
    # This is deliberately model-level (`meta:`) rather than controller-level
    # (PaperTrail's `info_for_paper_trail`): versions are written from jobs,
    # callbacks, rake tasks and the console too, and only the model hook covers
    # all of them. PaperTrail also includes its own controller module into
    # ActionController::Base after ours, so a controller-side override is not
    # reliably ours to win.
    CORRELATION_META = {
      correlation_id: ->(_record) { LlamaBotRails::Current.correlation_id },
      request_id: ->(_record) { LlamaBotRails::Current.request_id },
      source: ->(_record) { LlamaBotRails::Current.source }
    }.freeze

    included do
      if LlamaBotRails::Auditable.paper_trail_available?
        has_paper_trail(
          # `skip` means the value is never written to the version at all —
          # that is what keeps secrets out of the audit log. `ignore` would
          # still persist them.
          skip: LlamaBotRails::Auditable.sensitive_attributes_for(self),
          ignore: LlamaBotRails::Auditable.ignored_attributes_for(self),
          meta: LlamaBotRails::Auditable::CORRELATION_META,
          versions: { name: :versions }
        )
      end

      has_many :activity_events,
               ->(record) { where(subject_type: LlamaBotRails::ActivityEvent.subject_type_for(record)).order(occurred_at: :desc) },
               class_name: "LlamaBotRails::ActivityEvent",
               foreign_key: :subject_id,
               primary_key: :id,
               inverse_of: false
    end

    class_methods do
      # Restrict versioning to a whitelist of columns.
      def audit_only(*attributes)
        return unless LlamaBotRails::Auditable.paper_trail_available?

        watched = attributes.flatten.map(&:to_s)
        has_paper_trail(
          only: watched,
          skip: LlamaBotRails::Auditable.sensitive_attributes_for(self),
          meta: LlamaBotRails::Auditable::CORRELATION_META,
          versions: { name: :versions }
        )
      end
    end

    def self.paper_trail_available?
      defined?(::PaperTrail) && ::PaperTrail.respond_to?(:request)
    end

    # Intersected with the model's real columns: PaperTrail is happy either
    # way, but keeping the list tight makes `skip` readable in the console.
    def self.sensitive_attributes_for(model)
      configured = LlamaBotRails.config.activity_sensitive_attributes || []
      patterns = LlamaBotRails.config.activity_sensitive_attribute_patterns || []

      model.column_names.select do |column|
        configured.include?(column) || patterns.any? { |pattern| column.match?(pattern) }
      end
    rescue StandardError
      # No table yet (fresh app, migration pending) — nothing to skip.
      []
    end

    def self.ignored_attributes_for(model)
      ignored = LlamaBotRails.config.activity_ignored_attributes || []
      model.column_names & ignored.map(&:to_s)
    rescue StandardError
      []
    end
  end
end
