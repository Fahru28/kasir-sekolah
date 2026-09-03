module LlamaBotRails
  class UserFeedback < ApplicationRecord
    STATUSES = ['open', 'under_review', 'acknowledged', 'in_progress', 'resolved', 'closed'].freeze
    FEEDBACK_TYPES = ['bug', 'suggestion', 'question', 'complaint', 'praise', 'general'].freeze

    # Associations
    has_many :taggings, as: :taggable, class_name: 'LlamaBotRails::Tagging', dependent: :destroy
    has_many :tags, through: :taggings, class_name: 'LlamaBotRails::Tag'
    has_many :comments, as: :commentable, class_name: 'LlamaBotRails::FeedbackComment', dependent: :destroy
    has_many :notifications, as: :notifiable, class_name: 'LlamaBotRails::Notification', dependent: :destroy

    # Active Storage - any file type
    has_many_attached :attachments

    # Validations - kept loose to allow quick feedback submission
    # `title` is NOT NULL in the database, so allowing it blank here meant a POST that
    # omitted it passed every validation, reached the INSERT and raised
    # NotNullViolation — an unrescued 500 that renders the FULL developer error page,
    # because Leo boxes run RAILS_ENV=development in production. Anonymous feedback
    # opened that path to anyone. Validating instead turns it into the clean 422 the
    # controller already renders for a failed save.
    validates :title, presence: true, length: { maximum: 255 }
    validates :status, inclusion: { in: STATUSES }, allow_blank: true
    validates :feedback_type, inclusion: { in: FEEDBACK_TYPES }, allow_blank: true
    # A signed-out submission has no user by definition. The column is nullable so the
    # row can exist; this keeps the old guarantee for every app that has not opted in.
    # display_author already falls back to user_email || 'Anonymous'.
    validates :user_id, presence: true,
              unless: -> { LlamaBotRails.config.anonymous_feedback_enabled }

    # Scopes
    scope :ordered, -> { order(created_at: :desc) }
    scope :by_status, ->(status) { where(status: status) }
    scope :by_type, ->(type) { where(feedback_type: type) }
    scope :open_items, -> { where(status: ['open', 'under_review', 'acknowledged', 'in_progress']) }
    scope :resolved_items, -> { where(status: ['resolved', 'closed']) }
    scope :high_priority, -> { where(priority: [2, 3]) }

    # Multi-select filter scopes
    scope :by_statuses, ->(statuses) { where(status: Array(statuses)) }
    scope :excluding_statuses, ->(statuses) { where.not(status: Array(statuses)).where.not(status: nil) }
    scope :by_types, ->(types) { where(feedback_type: Array(types)) }
    scope :excluding_types, ->(types) { where.not(feedback_type: Array(types)) }

    # Date range scopes
    scope :created_after, ->(date) { where('created_at >= ?', date.to_date.beginning_of_day) }
    scope :created_before, ->(date) { where('created_at <= ?', date.to_date.end_of_day) }
    scope :created_between, ->(start_date, end_date) { created_after(start_date).created_before(end_date) }

    # User resolution using the engine's resolver
    def user
      LlamaBotRails.user_resolver&.call(user_id)
    end

    def display_author
      user&.email || user_email || 'Anonymous'
    end

    def self.grouped_by_status
      STATUSES.index_with { |status| where(status: status).ordered }
    end

    def resolved?
      ['resolved', 'closed'].include?(status)
    end

    def resolve!(resolution_text = nil)
      update!(
        status: 'resolved',
        resolution: resolution_text,
        resolved_at: Time.current
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
