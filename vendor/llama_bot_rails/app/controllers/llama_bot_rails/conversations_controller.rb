module LlamaBotRails
  class ConversationsController < ApplicationController
    include Authorizable

    layout "llama_bot_rails/inbox"
    before_action :require_llama_user!
    before_action :set_conversation, only: [:show, :messages]
    before_action :authorize_conversation_access!, only: [:show, :messages]

    # GET /conversations
    def index
      @conversations = Conversation
        .for_user(current_llama_user.id)
        .recent
        .includes(:participants, :messages)

      # Load users for the dropdown (exclude current user)
      @users = load_available_users.reject { |u| u.id == current_llama_user.id }

      respond_to do |format|
        format.html
        format.json do
          render json: @conversations.map { |c| conversation_json(c) }
        end
      end
    end

    # GET /conversations/:id
    def show
      # Mark as read when viewing
      participant = @conversation.participants.find_by(user_id: current_llama_user.id)
      participant&.mark_as_read!

      @messages = @conversation.messages.chronological.limit(100)

      respond_to do |format|
        format.html
        format.json do
          render json: {
            conversation: conversation_json(@conversation),
            messages: @messages.map { |m| message_json(m) }
          }
        end
      end
    end

    # POST /conversations
    def create
      recipient_id = params[:recipient_id]&.to_i

      unless recipient_id && recipient_id != current_llama_user.id
        respond_to do |format|
          format.html { redirect_to conversations_path, alert: 'Invalid recipient' }
          format.json { render json: { error: 'Invalid recipient' }, status: :unprocessable_entity }
        end
        return
      end

      # Verify recipient exists
      recipient = LlamaBotRails.user_resolver&.call(recipient_id)
      unless recipient
        respond_to do |format|
          format.html { redirect_to conversations_path, alert: 'Recipient not found' }
          format.json { render json: { error: 'Recipient not found' }, status: :not_found }
        end
        return
      end

      @conversation = Conversation.find_or_create_between(current_llama_user.id, recipient_id)

      respond_to do |format|
        format.html { redirect_to conversation_path(@conversation) }
        format.json { render json: conversation_json(@conversation), status: :created }
      end
    end

    # GET /conversations/:id/messages
    def messages
      before_id = params[:before]
      limit = [params.fetch(:limit, 50).to_i, 100].min

      messages_scope = @conversation.messages.chronological
      messages_scope = messages_scope.where('id < ?', before_id) if before_id.present?
      @messages = messages_scope.limit(limit)

      # Mark as read
      participant = @conversation.participants.find_by(user_id: current_llama_user.id)
      participant&.mark_as_read!

      render json: {
        messages: @messages.map { |m| message_json(m) },
        has_more: @messages.count == limit
      }
    end

    private

    def load_available_users
      # Try to load users from Devise configuration
      if defined?(Devise)
        default_scope = Devise.default_scope
        user_class = Devise.mappings[default_scope].to
        user_class.all.order(:email)
      else
        []
      end
    end

    def set_conversation
      @conversation = Conversation.find(params[:id])
    end

    def authorize_conversation_access!
      unless @conversation.participant_user_ids.include?(current_llama_user.id)
        respond_to do |format|
          format.html { redirect_to conversations_path, alert: 'You do not have access to this conversation.' }
          format.json { render json: { error: 'Unauthorized' }, status: :forbidden }
        end
      end
    end

    def conversation_json(conversation)
      {
        id: conversation.id,
        title: conversation.display_name_for(current_llama_user.id),
        conversation_type: conversation.conversation_type,
        unread_count: conversation.unread_count_for(current_llama_user.id),
        last_message: conversation.last_message ? message_json(conversation.last_message) : nil,
        participants: conversation.participants.map { |p|
          user = p.user
          { id: p.user_id, email: user&.email || 'Unknown' }
        },
        updated_at: conversation.updated_at.iso8601
      }
    end

    def message_json(message)
      {
        id: message.id,
        body: message.body,
        sender_id: message.sender_id,
        sender_name: message.sender_display_name,
        created_at: message.created_at.iso8601,
        is_own: message.sender_id == current_llama_user.id
      }
    end
  end
end
