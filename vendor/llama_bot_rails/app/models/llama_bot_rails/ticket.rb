module LlamaBotRails
  class Ticket < ApplicationRecord
    STATUSES = ['backlog', 'assigned', 'in_progress', 'review', 'incomplete', 'done'].freeze

    # Associations
    belongs_to :project, optional: true
    has_many :comments, class_name: 'LlamaBotRails::TicketComment', dependent: :destroy
    has_many :traces, class_name: 'LlamaBotRails::TicketTrace', dependent: :destroy

    # Active Storage
    has_many_attached :images

    enum agent_result: { one_shot: 0, multi_shot: 1, failed: 2 }
    enum ticket_type: {
      feature_new_model: 0,
      feature_extend_existing_model: 1,
      bug_debug: 2,
      ux_copy: 3,
      ux_layout: 4,
      builder_integration: 5
    }

    validates :title, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }

    scope :ordered, -> { order(position: :asc) }

    def self.grouped_by_status
      STATUSES.index_with { |status| where(status: status).ordered }
    end

    # Helper methods for tracking
    def work_duration
      return nil unless work_started_at && work_completed_at
      work_completed_at - work_started_at
    end

    def work_duration_in_minutes
      return nil unless work_duration
      (work_duration / 60).round
    end

    def total_tokens
      (tokens_to_create_ticket || 0) + (tokens_to_implement_ticket || 0)
    end

    def total_trace_tokens
      traces.sum(:tokens_used) || 0
    end

    # Migrate legacy langsmith_url to traces
    def migrate_langsmith_url_to_trace!
      return if langsmith_url.blank?
      return if traces.exists?(langsmith_url: langsmith_url)

      traces.create!(
        langsmith_url: langsmith_url,
        trace_type: :creation
      )
    end
  end
end
