module LlamaBotRails
  class DirectMessagesController < ApplicationController
    include Authorizable

    before_action :require_llama_user!
    before_action :set_conversation
    before_action :authorize_conversation_access!

    # POST /conversations/:conversation_id/messages
    def create
      @message = @conversation.messages.new(message_params)
      @message.sender_id = current_llama_user.id

      if @message.save
        # Update participant's last activity
        participant = @conversation.participants.find_by(user_id: current_llama_user.id)
        participant&.mark_as_read!

        respond_to do |format|
          format.html { redirect_to conversation_path(@conversation) }
          format.json { render json: message_json(@message), status: :created }
        end
      else
        respond_to do |format|
          format.html { redirect_to conversation_path(@conversation), alert: 'Failed to send message.' }
          format.json { render json: { errors: @message.errors.full_messages }, status: :unprocessable_entity }
        end
      end
    end

    private

    def set_conversation
      @conversation = Conversation.find(params[:conversation_id])
    end

    def authorize_conversation_access!
      unless @conversation.participant_user_ids.include?(current_llama_user.id)
        respond_to do |format|
          format.html { redirect_to conversations_path, alert: 'Unauthorized' }
          format.json { render json: { error: 'Unauthorized' }, status: :forbidden }
        end
      end
    end

    def message_params
      params.require(:direct_message).permit(:body)
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
