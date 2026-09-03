module LlamaBotRails
  class TicketsController < ApplicationController
    include Authorizable

    layout "llama_bot_rails/inbox"

    # This controller had no authorization of any kind. The only thing keeping
    # the ticket board away from ordinary users was the chat UI hiding its tab
    # (data-engineer-only in chat.html) — the URL itself answered anybody. That
    # was survivable while nothing linked to it; the shared Inbox tab bar links
    # to it from Feedback, which regular users can reach, so it is gated here.
    #
    # require_authentication! (not require_llama_user!) so open, single-operator
    # boxes behave exactly as they do today: the gate switches on with the
    # app-wide lockdown, not before it.
    before_action :require_authentication!
    before_action :require_ticket_access!
    before_action :set_ticket, only: [:show, :edit, :update, :destroy, :remove_image, :share_attachment]

    def index
      @projects = Project.ordered
      @selected_project_id = params[:project_id]

      if @selected_project_id.present?
        @tickets = Ticket.where(project_id: @selected_project_id).grouped_by_status
      else
        @tickets = Ticket.grouped_by_status
      end
    end

    def timeline
      @projects = Project.ordered
      @selected_project_id = params[:project_id]

      # Base query
      tickets_query = Ticket.all
      tickets_query = tickets_query.where(project_id: @selected_project_id) if @selected_project_id.present?

      # Order by created_at for timeline display
      @tickets = tickets_query.order(created_at: :asc)

      # Calculate date range for timeline
      if @tickets.any?
        @earliest_date = @tickets.minimum(:created_at)
        @latest_date = @tickets.maximum(:created_at)
      else
        @earliest_date = Time.current.beginning_of_month
        @latest_date = Time.current
      end

      # Default view scale
      @scale = params[:scale] || 'month'

      # Stats for header
      @ticket_count = @tickets.count
      @date_range_days = (@latest_date.to_date - @earliest_date.to_date).to_i + 1
    end

    def show
      respond_to do |format|
        format.html
        format.json { render json: @ticket }
      end
    end

    def new
      @ticket = Ticket.new
    end

    def edit
    end

    def create
      @ticket = Ticket.new(ticket_params)
      if @ticket.save
        redirect_to ticket_path(@ticket), notice: "Ticket was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      respond_to do |format|
        if @ticket.update(ticket_params)
          format.html { redirect_to ticket_path(@ticket), notice: "Ticket was successfully updated." }
          format.json { render json: @ticket, status: :ok }
        else
          format.html { render :edit, status: :unprocessable_entity }
          format.json { render json: @ticket.errors, status: :unprocessable_entity }
        end
      end
    end

    def destroy
      @ticket.destroy!
      redirect_to tickets_path, notice: "Ticket was successfully destroyed."
    end

    def move
      @ticket = Ticket.find(params[:id])
      if @ticket.update(status: params[:status], position: params[:position].to_i)
        render json: { success: true }
      else
        render json: { success: false, error: @ticket.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def remove_image
      image = @ticket.images.find(params[:image_id])
      image.purge
      respond_to do |format|
        format.html { redirect_to ticket_path(@ticket), notice: "Image removed." }
        format.json { head :no_content }
      end
    end

    def share_attachment
      attachment_id = params[:attachment_id] || request.request_parameters.dig(:attachment_id)
      attachment = @ticket.images.find(attachment_id)
      shared_link = SharedLink.find_or_create_by!(attachment: attachment)

      render json: {
        url: shared_link_url(shared_link.token),
        token: shared_link.token
      }
    end

    private

    def set_ticket
      @ticket = Ticket.find(params[:id])
    end

    def ticket_params
      params.require(:ticket).permit(
        :title, :description, :status, :position, :notes,
        :ticket_type, :agent_result, :agent_notes, :research_notes, :langsmith_url,
        :project_id,
        :tokens_to_create_ticket, :tokens_to_implement_ticket, :llm_model,
        :work_started_at, :work_completed_at,
        :points_estimate, :points_actual,
        images: []
      )
    end
  end
end
