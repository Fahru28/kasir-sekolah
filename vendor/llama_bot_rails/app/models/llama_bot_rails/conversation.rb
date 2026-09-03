module LlamaBotRails
  class Conversation < ApplicationRecord
    TYPES = %w[direct group].freeze

    has_many :participants, class_name: 'LlamaBotRails::ConversationParticipant', dependent: :destroy
    has_many :messages, class_name: 'LlamaBotRails::DirectMessage', dependent: :destroy

    validates :conversation_type, inclusion: { in: TYPES }

    scope :for_user, ->(user_id) {
      joins(:participants).where(llama_bot_rails_conversation_participants: { user_id: user_id })
    }
    scope :recent, -> { order(updated_at: :desc) }
    scope :direct, -> { where(conversation_type: 'direct') }

    # Find or create a direct conversation between two users
    def self.find_or_create_between(user_id_1, user_id_2)
      return nil if user_id_1 == user_id_2

      user_ids = [user_id_1, user_id_2].sort

      # Find existing direct conversation between these two users
      existing = direct
        .joins(:participants)
        .where(llama_bot_rails_conversation_participants: { user_id: user_ids })
        .group('llama_bot_rails_conversations.id')
        .having('COUNT(DISTINCT llama_bot_rails_conversation_participants.user_id) = 2')
        .first

      return existing if existing

      # Create new conversation
      transaction do
        conversation = create!(conversation_type: 'direct')
        conversation.participants.create!(user_id: user_id_1, joined_at: Time.current)
        conversation.participants.create!(user_id: user_id_2, joined_at: Time.current)
        conversation
      end
    end

    def participant_user_ids
      participants.pluck(:user_id)
    end

    def other_participants(current_user_id)
      participants.where.not(user_id: current_user_id)
    end

    def other_participant(current_user_id)
      other_participants(current_user_id).first
    end

    def unread_count_for(user_id)
      participant = participants.find_by(user_id: user_id)
      return 0 unless participant

      if participant.last_read_at
        messages.where('created_at > ?', participant.last_read_at).count
      else
        messages.count
      end
    end

    def last_message
      messages.order(created_at: :desc).first
    end

    def display_name_for(current_user_id)
      if title.present?
        title
      elsif conversation_type == 'direct'
        other = other_participant(current_user_id)
        other_user = LlamaBotRails.user_resolver&.call(other&.user_id)
        other_user&.email || 'Unknown User'
      else
        'Group Conversation'
      end
    end
  end
end
