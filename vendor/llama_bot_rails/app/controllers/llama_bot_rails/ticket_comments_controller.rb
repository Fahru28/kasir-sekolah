module LlamaBotRails
  class TicketCommentsController < ApplicationController
    before_action :set_ticket

    def create
      @comment = @ticket.comments.build(comment_params)

      # Try to set user info from current_user if available in host app
      if defined?(current_user) && current_user.present?
        @comment.user_id = current_user.id
        @comment.author_name ||= current_user.try(:name) || current_user.try(:email)
      end

      if @comment.save
        respond_to do |format|
          format.html { redirect_to ticket_path(@ticket), notice: "Comment added." }
          format.json { render json: @comment, status: :created }
        end
      else
        respond_to do |format|
          format.html { redirect_to ticket_path(@ticket), alert: @comment.errors.full_messages.join(", ") }
          format.json { render json: @comment.errors, status: :unprocessable_entity }
        end
      end
    end

    def destroy
      @comment = @ticket.comments.find(params[:id])
      @comment.destroy!
      respond_to do |format|
        format.html { redirect_to ticket_path(@ticket), notice: "Comment deleted." }
        format.json { head :no_content }
      end
    end

    private

    def set_ticket
      @ticket = Ticket.find(params[:ticket_id])
    end

    def comment_params
      params.require(:ticket_comment).permit(:body, :author_name)
    end
  end
end
