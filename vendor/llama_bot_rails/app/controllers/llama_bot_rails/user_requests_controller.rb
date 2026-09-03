module LlamaBotRails
  class UserRequestsController < ApplicationController
    include Authorizable

    layout "llama_bot_rails/inbox"
    before_action :require_llama_user!, except: [:index]
    before_action :set_request, only: [:show, :edit, :update, :destroy, :add_tag, :remove_tag, :respond_to_request, :remove_attachment, :share_attachment]
    before_action :authorize_request_access!, only: [:show, :edit, :update, :destroy]

    def index
      @requests = if can?(:view_all_requests)
        UserRequest.ordered
      elsif current_llama_user
        UserRequest.where(user_id: current_llama_user.id).ordered
      else
        UserRequest.none
      end

      @requests = @requests.by_status(params[:status]) if params[:status].present?
      @requests = @requests.by_type(params[:request_type]) if params[:request_type].present?
      @tags = Tag.ordered
    end

    def dashboard
      authorize!(:view_all_requests)
      return if performed?

      @requests_by_status = UserRequest.grouped_by_status
      @popular_requests = UserRequest.by_votes.limit(10)
      @tags = Tag.popular.limit(20)
      @stats = {
        total: UserRequest.count,
        pending: UserRequest.pending.count,
        active: UserRequest.active.count,
        completed: UserRequest.where(status: 'completed').count
      }
    end

    def show
      @comments = @request.comments.top_level.chronological
    end

    def new
      authorize!(:submit_request)
      return if performed?

      @request = UserRequest.new
    end

    def create
      authorize!(:submit_request)
      return if performed?

      @request = UserRequest.new(request_params)
      @request.user_id = current_llama_user.id
      @request.user_email = current_llama_user.email if current_llama_user.respond_to?(:email)

      if @request.save
        redirect_to user_request_path(@request), notice: "Request submitted successfully."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      respond_to do |format|
        if @request.update(request_params)
          format.html { redirect_to user_request_path(@request), notice: "Request updated successfully." }
          format.json { render json: @request, status: :ok }
        else
          format.html { render :edit, status: :unprocessable_entity }
          format.json { render json: @request.errors, status: :unprocessable_entity }
        end
      end
    end

    def destroy
      @request.destroy!
      redirect_to user_requests_path, notice: "Request deleted successfully."
    end

    def add_tag
      authorize!(:manage_tags)
      return if performed?

      tag = Tag.find(params[:tag_id])
      @request.tags << tag unless @request.tags.include?(tag)
      redirect_to user_request_path(@request), notice: "Tag added."
    end

    def remove_tag
      authorize!(:manage_tags)
      return if performed?

      tag = Tag.find(params[:tag_id])
      @request.tags.delete(tag)
      redirect_to user_request_path(@request), notice: "Tag removed."
    end

    def respond_to_request
      authorize!(:moderate_feedback)
      return if performed?

      @request.respond!(params[:response])
      redirect_to user_request_path(@request), notice: "Response sent."
    end

    def remove_attachment
      authorize!(:moderate_feedback)
      return if performed?

      attachment = @request.attachments.find(params[:attachment_id])
      attachment.purge
      redirect_to user_request_path(@request), notice: "Attachment removed."
    end

    def share_attachment
      attachment_id = params[:attachment_id] || request_parameters.dig(:attachment_id)
      attachment = @request.attachments.find(attachment_id)
      shared_link = SharedLink.find_or_create_by!(attachment: attachment)

      render json: {
        url: shared_link_url(shared_link.token),
        token: shared_link.token
      }
    end

    private

    def set_request
      @request = UserRequest.find(params[:id])
    end

    def authorize_request_access!
      return if can?(:view_all_requests) || @request.user_id == current_llama_user&.id

      redirect_to user_requests_path, alert: "You can only access your own requests."
    end

    def request_params
      permitted = [:title, :description, :request_type, attachments: []]
      permitted += [:status, :priority, :admin_notes, :response] if can?(:moderate_feedback)
      params.require(:user_request).permit(permitted)
    end
  end
end
