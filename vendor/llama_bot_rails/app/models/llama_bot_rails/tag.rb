module LlamaBotRails
  class Tag < ApplicationRecord
    has_many :taggings, dependent: :destroy
    has_many :user_feedbacks, through: :taggings, source: :taggable, source_type: 'LlamaBotRails::UserFeedback'
    has_many :user_requests, through: :taggings, source: :taggable, source_type: 'LlamaBotRails::UserRequest'

    validates :name, presence: true, uniqueness: { case_sensitive: false }
    validates :color, format: { with: /\A#[0-9A-Fa-f]{6}\z/, message: "must be a valid hex color" }, allow_blank: true

    scope :ordered, -> { order(name: :asc) }
    scope :popular, -> { left_joins(:taggings).group(:id).order('COUNT(llama_bot_rails_taggings.id) DESC') }

    before_validation :set_default_color

    def usage_count
      taggings.count
    end

    private

    def set_default_color
      self.color ||= '#6366f1'
    end
  end
end
