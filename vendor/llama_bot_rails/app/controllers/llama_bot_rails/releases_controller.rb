module LlamaBotRails
  class ReleasesController < ApplicationController
    include Authorizable

    layout false
    before_action :require_authentication!
    before_action :authorize_releases_admin!, only: [:new, :create, :edit, :update, :destroy, :notify]
    before_action :set_release, only: [:show, :edit, :update, :destroy, :notify]

    def index
      releases = can?(:manage_releases) ? Release.all : Release.published
      @releases = releases.ordered
      @current_release = Release.current

      respond_to do |format|
        format.html
        format.json { render json: releases_json(@releases) }
      end
    end

    def show
      respond_to do |format|
        format.html
        format.json { render json: release_json(@release) }
      end
    end

    def new
      @release = Release.new(released_at: Time.current)
    end

    def create
      @release = Release.new(release_params)

      if @release.save
        redirect_to release_path(@release), notice: "Release created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @release.update(release_params)
        redirect_to release_path(@release), notice: "Release updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @release.destroy!
      redirect_to releases_path, notice: "Release deleted."
    end

    # Email the configured recipient list about this release (opt-in).
    def notify
      unless LlamaBotRails.config.release_email_enabled
        return redirect_to release_path(@release), alert: "Release emails are not enabled for this app."
      end

      recipients = Array(LlamaBotRails.config.release_notification_emails).reject(&:blank?)
      if recipients.empty?
        return redirect_to release_path(@release), alert: "No release notification recipients are configured."
      end

      LlamaBotRails::ReleaseMailer.new_release(@release).deliver_later
      @release.update(emailed_at: Time.current)
      redirect_to release_path(@release), notice: "Release email queued to #{recipients.size} recipient(s)."
    rescue => e
      Rails.logger.error("[[LlamaBot]] Failed to enqueue release email: #{e.message}")
      redirect_to release_path(@release), alert: "Could not queue the release email."
    end

    private

    def authorize_releases_admin!
      authorize!(:manage_releases)
    end

    def set_release
      @release = Release.find(params[:id])
    end

    def release_params
      params.require(:release).permit(:version, :title, :notes, :published, :released_at)
    end

    def releases_json(scope)
      { releases: scope.map { |r| release_json(r) } }
    end

    def release_json(release)
      {
        id: release.id,
        version: release.version,
        title: release.title,
        notes: release.notes,
        published: release.published,
        current: release.current?,
        released_at: release.released_at
      }
    end
  end
end
