module LlamaBotRails
  class TicketTrace < ApplicationRecord
    belongs_to :ticket

    enum trace_type: {
      creation: 0,
      implementation: 1,
      debugging: 2,
      other: 3
    }

    validates :langsmith_url, presence: true, unless: -> { langsmith_run_id.present? }

    scope :ordered, -> { order(created_at: :desc) }
    scope :chronological, -> { order(created_at: :asc) }

    def langsmith_url_with_fallback
      langsmith_url.presence || (langsmith_run_id.present? ? "https://smith.langchain.com/runs/#{langsmith_run_id}" : nil)
    end
  end
end
