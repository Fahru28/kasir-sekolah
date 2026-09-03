module LlamaBotRails
  class FeedbackCommentsController < ApplicationController
    include Authorizable

    before_action :require_llama_user!
    before_action :set_commentable

    def create
      @comment = @commentable.comments.new(comment_params)
      @comment.user_id = current_llama_user&.id
      @comment.author_name ||= current_llama_user&.email if current_llama_user.respond_to?(:email)
      @comment.is_admin_response = can?(:moderate_feedback)

      if @comment.save
        redirect_back fallback_location: polymorphic_path([@commentable]), notice: "Comment added."
      else
        redirect_back fallback_location: polymorphic_path([@commentable]), alert: "Failed to add comment: #{@comment.errors.full_messages.join(', ')}"
      end
    end

    # Authors fix their own typos. Moderators can delete a comment but may NOT
    # rewrite someone else's words, so edit is author-only (delete stays broader).
    def update
      @comment = FeedbackComment.find(params[:id])

      unless @comment.user_id.present? && @comment.user_id == current_llama_user&.id
        redirect_back fallback_location: polymorphic_path([@commentable]), alert: "Not authorized."
        return
      end

      new_attachments = params.dig(:feedback_comment, :attachments)

      if @comment.update(comment_update_params)
        # has_many_attached replaces on assign, so append explicitly instead of
        # letting an edit silently purge the attachments already on the comment.
        @comment.attachments.attach(new_attachments.compact_blank) if new_attachments.present?
        redirect_back fallback_location: polymorphic_path([@commentable]), notice: "Comment updated."
      else
        redirect_back fallback_location: polymorphic_path([@commentable]), alert: "Failed to update comment: #{@comment.errors.full_messages.join(', ')}"
      end
    end

    def destroy
      @comment = FeedbackComment.find(params[:id])

      unless can?(:moderate_feedback) || @comment.user_id == current_llama_user&.id
        redirect_back fallback_location: polymorphic_path([@commentable]), alert: "Not authorized."
        return
      end

      @comment.destroy!
      redirect_back fallback_location: polymorphic_path([@commentable]), notice: "Comment deleted."
    end

    def remove_attachment
      @comment = FeedbackComment.find(params[:id])

      unless can?(:moderate_feedback) || @comment.user_id == current_llama_user&.id
        redirect_back fallback_location: polymorphic_path([@commentable]), alert: "Not authorized."
        return
      end

      attachment = @comment.attachments.find(params[:attachment_id])
      attachment.purge
      redirect_back fallback_location: polymorphic_path([@commentable]), notice: "Attachment removed."
    end

    private

    def set_commentable
      if params[:user_feedback_id]
        @commentable = UserFeedback.find(params[:user_feedback_id])
      elsif params[:user_request_id]
        @commentable = UserRequest.find(params[:user_request_id])
      end
    end

    def comment_params
      params.require(:feedback_comment).permit(:body, :author_name, :parent_id, mentioned_user_ids: [], attachments: [])
    end

    def comment_update_params
      params.require(:feedback_comment).permit(:body)
    end
  end
end
