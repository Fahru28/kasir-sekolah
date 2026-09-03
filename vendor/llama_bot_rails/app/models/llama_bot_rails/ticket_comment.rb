module LlamaBotRails
  class TicketComment < ApplicationRecord
    belongs_to :ticket

    validates :body, presence: true

    scope :ordered, -> { order(created_at: :desc) }
    scope :chronological, -> { order(created_at: :asc) }

    def display_author
      author_name.presence || 'Anonymous'
    end
  end
end
