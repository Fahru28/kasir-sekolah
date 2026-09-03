module LlamaBotRails
  class Project < ApplicationRecord
    has_many :tickets, dependent: :nullify

    validates :name, presence: true

    scope :ordered, -> { order(name: :asc) }

    def ticket_count
      tickets.count
    end

    def completed_ticket_count
      tickets.where(status: 'done').count
    end
  end
end
