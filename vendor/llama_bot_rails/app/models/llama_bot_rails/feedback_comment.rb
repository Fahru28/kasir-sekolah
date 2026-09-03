module LlamaBotRails
  class FeedbackComment < ApplicationRecord
    belongs_to :commentable, polymorphic: true
    belongs_to :parent, class_name: 'LlamaBotRails::FeedbackComment', optional: true
    has_many :replies, class_name: 'LlamaBotRails::FeedbackComment', foreign_key: :parent_id, dependent: :destroy
    has_many :notifications, as: :notifiable, class_name: 'LlamaBotRails::Notification', dependent: :destroy
    has_many_attached :attachments

    validates :body, presence: true

    scope :ordered, -> { order(created_at: :desc) }
    scope :chronological, -> { order(created_at: :asc) }
    scope :admin_responses, -> { where(is_admin_response: true) }
    scope :top_level, -> { where(parent_id: nil) }

    after_create :create_comment_notifications
    after_create :create_mention_notifications

    def reply?
      parent_id.present?
    end

    # A save that only attaches a file still bumps updated_at, so allow a small
    # window before calling a comment "edited".
    def edited?
      updated_at.present? && created_at.present? && (updated_at - created_at) > 1.second
    end

    # Only the author may rewrite their own words. Moderators can still delete.
    def editable_by?(user)
      user.present? && user_id.present? && user_id == user.id
    end

    def user
      LlamaBotRails.user_resolver&.call(user_id) if user_id
    end

    def display_author
      if is_admin_response
        "Admin: #{author_name.presence || 'Staff'}"
      else
        author_name.presence || user&.email || 'Anonymous'
      end
    end

    private

    def create_comment_notifications
      return unless commentable.is_a?(UserFeedback)

      notified_user_ids = []

      # Notify the feedback owner (unless they wrote the comment)
      if commentable.user_id.present? && commentable.user_id != user_id
        Notification.create!(
          user_id: commentable.user_id,
          actor_id: user_id,
          notifiable: self,
          notification_type: 'feedback_comment',
          message: "#{display_author} commented on your feedback: #{commentable.title}",
          metadata: { feedback_id: commentable.id }
        )
        notified_user_ids << commentable.user_id
      end

      # Notify previous commenters on this feedback (except the current commenter and feedback owner)
      previous_commenters = commentable.comments
        .where.not(user_id: [user_id, nil])
        .where.not(user_id: notified_user_ids)
        .distinct
        .pluck(:user_id)

      previous_commenters.each do |commenter_id|
        Notification.create!(
          user_id: commenter_id,
          actor_id: user_id,
          notifiable: self,
          notification_type: 'feedback_comment',
          message: "#{display_author} also commented on: #{commentable.title}",
          metadata: { feedback_id: commentable.id }
        )
      end
    end

    def create_mention_notifications
      return unless commentable.is_a?(UserFeedback)
      return if mentioned_user_ids.blank?

      mentioned_user_ids.each do |mentioned_id|
        mentioned_id = mentioned_id.to_i
        next if mentioned_id == user_id # Don't notify self

        Notification.create!(
          user_id: mentioned_id,
          actor_id: user_id,
          notifiable: self,
          notification_type: 'feedback_mention',
          message: "#{display_author} tagged you in a comment on: #{commentable.title}",
          metadata: { feedback_id: commentable.id, comment_id: id }
        )
      end
    end
  end
end
