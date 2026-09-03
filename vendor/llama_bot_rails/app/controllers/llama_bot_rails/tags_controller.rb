module LlamaBotRails
  class TagsController < ApplicationController
    include Authorizable

    # Reached from the Requests and Feedback dashboards, so it renders inside the
    # Inbox chrome: with `layout false` it was a one-way door — a page with no tab
    # bar and no way back except the browser's back button. No tab shows active
    # here, which is the correct state for a sub-page of the group.
    layout "llama_bot_rails/inbox"
    before_action :authorize_tag_management!
    before_action :set_tag, only: [:edit, :update, :destroy]

    def index
      @tags = Tag.popular
    end

    def new
      @tag = Tag.new
    end

    def create
      @tag = Tag.new(tag_params)
      if @tag.save
        redirect_to tags_path, notice: "Tag created successfully."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @tag.update(tag_params)
        redirect_to tags_path, notice: "Tag updated successfully."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @tag.destroy!
      redirect_to tags_path, notice: "Tag deleted."
    end

    private

    def authorize_tag_management!
      authorize!(:manage_tags)
    end

    def set_tag
      @tag = Tag.find(params[:id])
    end

    def tag_params
      params.require(:tag).permit(:name, :color, :description)
    end
  end
end
