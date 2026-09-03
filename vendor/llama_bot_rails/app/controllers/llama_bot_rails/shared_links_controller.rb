module LlamaBotRails
  class SharedLinksController < ApplicationController
    # Public access - skip all authentication
    skip_before_action :require_authentication!, raise: false
    skip_before_action :authenticate_user!, raise: false

    layout false

    # GET /llama_bot/shared/:token
    def show
      @shared_link = SharedLink.find_by!(token: params[:token])

      if @shared_link.expired?
        render :expired, status: :gone
        return
      end

      @shared_link.increment_view_count!
      @blob = @shared_link.blob

      respond_to do |format|
        format.html # Renders show.html.erb with video player
        format.json { render json: shared_link_json }
      end
    rescue ActiveRecord::RecordNotFound
      render :not_found, status: :not_found
    end

    # GET /llama_bot/shared/:token/download
    def download
      @shared_link = SharedLink.find_by!(token: params[:token])

      if @shared_link.expired?
        render :expired, status: :gone
        return
      end

      redirect_to main_app.rails_blob_path(@shared_link.blob, disposition: 'attachment'),
                  allow_other_host: true
    rescue ActiveRecord::RecordNotFound
      render :not_found, status: :not_found
    end

    # GET /llama_bot/shared/:token/stream
    # Direct stream URL for embedding in video/img tags
    def stream
      @shared_link = SharedLink.find_by!(token: params[:token])

      return head(:gone) if @shared_link.expired?

      redirect_to main_app.rails_blob_path(@shared_link.blob, disposition: 'inline'),
                  allow_other_host: true
    rescue ActiveRecord::RecordNotFound
      head :not_found
    end

    private

    def shared_link_json
      {
        token: @shared_link.token,
        filename: @shared_link.filename.to_s,
        content_type: @shared_link.content_type,
        size: @shared_link.byte_size,
        view_count: @shared_link.view_count,
        video: @shared_link.video?,
        image: @shared_link.image?,
        stream_url: stream_shared_link_url(@shared_link.token),
        download_url: download_shared_link_url(@shared_link.token)
      }
    end
  end
end
