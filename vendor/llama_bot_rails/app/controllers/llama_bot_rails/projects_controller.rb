module LlamaBotRails
  class ProjectsController < ApplicationController
    include Authorizable

    # Reached from the ticket views, so it renders inside the Inbox chrome
    # rather than dead-ending on a page with no tab bar. Authorizable is also
    # what lets that bar decide whether to show the Tickets tab at all.
    layout "llama_bot_rails/inbox"

    # Gated on :view_tickets, not a permission of its own: a project page lists
    # that project's tickets, so leaving this open would hand out the ticket
    # board that TicketsController now refuses.
    before_action :require_authentication!
    before_action :require_ticket_access!
    before_action :set_project, only: [:show, :edit, :update, :destroy]

    def index
      @projects = Project.ordered
    end

    def show
      @tickets = @project.tickets.grouped_by_status
    end

    def new
      @project = Project.new
    end

    def edit
    end

    def create
      @project = Project.new(project_params)
      if @project.save
        redirect_to project_path(@project), notice: "Project was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @project.update(project_params)
        redirect_to project_path(@project), notice: "Project was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @project.destroy!
      redirect_to projects_path, notice: "Project was successfully deleted."
    end

    private

    def set_project
      @project = Project.find(params[:id])
    end

    def project_params
      params.require(:project).permit(:name, :description)
    end
  end
end
