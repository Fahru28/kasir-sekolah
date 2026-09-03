module LlamaBotRails
  class UserRequest < ApplicationRecord
    STATUSES = ['submitted', 'under_review', 'planned', 'in_progress', 'completed', 'declined'].freeze
    REQUEST_TYPES = ['feature', 'enhancement', 'integration', 'content', 'other'].freeze

    # Associations
    has_many :taggings, as: :taggable, class_name: 'LlamaBotRails::Tagging', dependent: :destroy
    has_many :tags, through: :taggings, class_name: 'LlamaBotRails::Tag'
    has_many :comments, as: :commentable, class_name: 'LlamaBotRails::FeedbackComment', dependent: :destroy

    # Active Storage - any file type
    has_many_attached :attachments

    # Validations
    validates :title, presence: true, length: { maximum: 255 }
    validates :description, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :request_type, presence: true, inclusion: { in: REQUEST_TYPES }
    validates :user_id, presence: true

    # Scopes
    scope :ordered, -> { order(created_at: :desc) }
    scope :by_votes, -> { order(votes_count: :desc) }
    scope :by_status, ->(status) { where(status: status) }
    scope :by_type, ->(type) { where(request_type: type) }
    scope :pending, -> { where(status: ['submitted', 'under_review', 'planned']) }
    scope :active, -> { where(status: 'in_progress') }

    def user
      LlamaBotRails.user_resolver&.call(user_id)
    end

    def display_author
      user&.email || user_email || 'Anonymous'
    end

    def self.grouped_by_status
      STATUSES.index_with { |status| where(status: status).ordered }
    end

    def respond!(response_text)
      update!(
        response: response_text,
        responded_at: Time.current
      )
    end

    def priority_label
      case priority
      when 0 then 'Low'
      when 1 then 'Medium'
      when 2 then 'High'
      when 3 then 'Critical'
      else 'Unknown'
      end
    end
  end
end
