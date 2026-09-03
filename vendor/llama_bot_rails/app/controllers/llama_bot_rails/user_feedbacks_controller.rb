module LlamaBotRails
  class UserFeedbacksController < ApplicationController
    include Authorizable

    layout "llama_bot_rails/inbox"
    # `new` and `create` come off the hard identity gate and are re-gated on the flag by
    # require_feedback_submitter!. Submitting is not per-person; everything else here
    # still needs to know who you are.
    before_action :require_llama_user!, except: [:index, :show, :edit, :update, :dashboard,
                                                 :kanban, :move, :new, :create]
    before_action :require_feedback_submitter!, only: [:new, :create]
    before_action :verify_feedback_submission_token!, only: [:create]
    before_action :set_feedback, only: [:show, :edit, :update, :destroy, :add_tag, :remove_tag, :remove_attachment, :share_attachment, :move]

    def index
      # Show all feedback to everyone by default
      feedbacks = UserFeedback.ordered

      # Multi-value status filter with IS/IS NOT support
      # Handle both ?status=x&status=y and ?status[]=x&status[]=y formats
      status_param = params[:status]
      if status_param.present?
        statuses = status_param.is_a?(Array) ? status_param : Array(status_param)
        statuses = statuses.reject(&:blank?)
        Rails.logger.info "[FILTER DEBUG] status_mode=#{params[:status_mode]}, statuses=#{statuses.inspect}, raw_param=#{status_param.inspect}"
        if statuses.any?
          if params[:status_mode] == 'is_not'
            feedbacks = feedbacks.excluding_statuses(statuses)
          else
            feedbacks = feedbacks.by_statuses(statuses)
          end
        end
      end

      # Multi-value type filter with IS/IS NOT support
      if params[:feedback_type].present?
        types = Array(params[:feedback_type])
        if params[:type_mode] == 'is_not'
          feedbacks = feedbacks.excluding_types(types)
        else
          feedbacks = feedbacks.by_types(types)
        end
      end

      # Date range filter (created_at)
      if params[:date_start].present?
        feedbacks = feedbacks.created_after(Date.parse(params[:date_start]))
      end
      if params[:date_end].present?
        feedbacks = feedbacks.created_before(Date.parse(params[:date_end]))
      end

      feedbacks = feedbacks.where(user_id: params[:user_id]) if params[:user_id].present?

      @feedbacks = feedbacks.includes(:tags, :comments)

      # Group by user, with current user's feedback first
      @feedbacks_by_user = @feedbacks.group_by(&:user_id)

      # Reorder so current user is first
      if current_llama_user
        current_user_feedbacks = @feedbacks_by_user.delete(current_llama_user.id)
        @feedbacks_by_user = { current_llama_user.id => current_user_feedbacks }.merge(@feedbacks_by_user) if current_user_feedbacks
      end

      @tags = Tag.ordered
      @submitters = UserFeedback.distinct.pluck(:user_id, :user_email).reject { |id, _| id.nil? }
    end

    def dashboard
      @feedbacks_by_status = UserFeedback.grouped_by_status
      @recent_feedbacks = UserFeedback.ordered.limit(10)
      @tags = Tag.popular.limit(20)
      @stats = {
        total: UserFeedback.count,
        open: UserFeedback.open_items.count,
        resolved: UserFeedback.resolved_items.count,
        high_priority: UserFeedback.high_priority.count
      }
    end

    def kanban
      @feedbacks_by_status = UserFeedback.grouped_by_status
    end

    def move
      new_status = params[:status]

      unless UserFeedback::STATUSES.include?(new_status)
        render json: { success: false, error: 'Invalid status' }, status: :unprocessable_entity
        return
      end

      previous_status = @feedback.status
      if @feedback.update(status: new_status)
        notify_status_change(@feedback, previous_status)
        render json: { success: true, feedback: { id: @feedback.id, status: @feedback.status } }
      else
        render json: { success: false, error: @feedback.errors.full_messages.join(', ') }, status: :unprocessable_entity
      end
    end

    def show
      @comments = @feedback.comments.top_level.chronological
      @submitters = UserFeedback.distinct.pluck(:user_id, :user_email).reject { |id, _| id.nil? }
    end

    def new
      authorize!(:submit_feedback)
      return if performed?

      @feedback = UserFeedback.new
    end

    def create
      authorize!(:submit_feedback)
      return if performed?

      # Honeypot: a field the bubble never fills. Answer 201 with a success body so the
      # bot cannot tell it failed and tune its way past the trap.
      if params[:llama_hp].present?
        Rails.logger.info "[LlamaBotRails] feedback honeypot tripped from #{request.remote_ip}"
        respond_to do |format|
          format.html { redirect_to llama_bot_rails.root_path, notice: "Feedback submitted successfully." }
          format.json { render json: { success: true }, status: :created }
        end
        return
      end

      @feedback = UserFeedback.new(feedback_params)
      # A signed-out submission has no user. Do not assume one exists.
      @feedback.user_id = current_llama_user&.id
      @feedback.user_email =
        if current_llama_user.respond_to?(:email)
          current_llama_user.email
        else
          feedback_params[:user_email]
        end
      @feedback.submitted_ip = request.remote_ip

      # The floating feedback bubble submits with fetch(). A redirect response makes an
      # async submit depend on the browser's redirect handling, which surfaces in Chrome
      # as a network-stage "Failed to fetch" (SupportIncident #139, leo-manu). Answer
      # JSON requests with a stable API response; the HTML form keeps redirecting.
      if @feedback.save
        notify_managers_of_new_feedback(@feedback)
        respond_to do |format|
          format.html { redirect_to user_feedback_path(@feedback), notice: "Feedback submitted successfully." }
          format.json do
            render json: {
              success: true,
              id: @feedback.id,
              url: user_feedback_path(@feedback)
            }, status: :created
          end
        end
      else
        respond_to do |format|
          format.html { render :new, status: :unprocessable_entity }
          format.json do
            render json: {
              success: false,
              errors: @feedback.errors.full_messages
            }, status: :unprocessable_entity
          end
        end
      end
    end

    def edit
    end

    def update
      previous_status = @feedback.status
      respond_to do |format|
        if @feedback.update(feedback_params)
          notify_status_change(@feedback, previous_status)
          format.html { redirect_to user_feedback_path(@feedback), notice: "Feedback updated successfully." }
          format.json { render json: @feedback, status: :ok }
        else
          format.html { render :edit, status: :unprocessable_entity }
          format.json { render json: @feedback.errors, status: :unprocessable_entity }
        end
      end
    end

    def destroy
      @feedback.destroy!
      redirect_to user_feedbacks_path, notice: "Feedback deleted successfully."
    end

    def add_tag
      authorize!(:manage_tags)
      return if performed?

      tag = Tag.find(params[:tag_id])
      @feedback.tags << tag unless @feedback.tags.include?(tag)
      redirect_to user_feedback_path(@feedback), notice: "Tag added."
    end

    def remove_tag
      authorize!(:manage_tags)
      return if performed?

      tag = Tag.find(params[:tag_id])
      @feedback.tags.delete(tag)
      redirect_to user_feedback_path(@feedback), notice: "Tag removed."
    end

    def remove_attachment
      attachment = @feedback.attachments.find(params[:attachment_id])
      attachment.purge
      redirect_to user_feedback_path(@feedback), notice: "Attachment removed."
    end

    def share_attachment
      attachment_id = params[:attachment_id] || request.request_parameters.dig(:attachment_id)
      attachment = @feedback.attachments.find(attachment_id)
      shared_link = SharedLink.find_or_create_by!(attachment: attachment)

      render json: {
        url: shared_link_url(shared_link.token),
        token: shared_link.token
      }
    end

    private

    # Email the configured manager recipients that new feedback came in (opt-in).
    def notify_managers_of_new_feedback(feedback)
      return unless LlamaBotRails.config.feedback_email_enabled

      recipients = Array(LlamaBotRails.config.feedback_notification_emails).reject(&:blank?)
      return if recipients.empty?

      LlamaBotRails::FeedbackMailer.new_feedback(feedback).deliver_later
    rescue => e
      Rails.logger.error("[[LlamaBot]] Failed to enqueue new feedback email: #{e.message}")
    end

    # Notify the feedback owner when someone else changes the status. The
    # notification's after_create hook delivers the email (when enabled).
    def notify_status_change(feedback, previous_status)
      return if previous_status == feedback.status
      return if feedback.user_id.blank?
      return if feedback.user_id == current_llama_user&.id

      Notification.create!(
        user_id: feedback.user_id,
        actor_id: current_llama_user&.id,
        notifiable: feedback,
        notification_type: "feedback_status_change",
        message: "#{status_change_actor_label} changed the status of your feedback to \"#{feedback.status}\": #{feedback.title}",
        metadata: { feedback_id: feedback.id, status: feedback.status }
      )
    end

    def status_change_actor_label
      email = current_llama_user.respond_to?(:email) ? current_llama_user.email : nil
      email.presence || "A team member"
    end

    def set_feedback
      @feedback = UserFeedback.find(params[:id])
    end

    def feedback_params
      # Status and priority are editable by all users
      permitted = [:title, :description, :feedback_type, :status, :priority, :user_id,
                   :selected_element_html, :selected_element_selector, :selected_element_url,
                   attachments: []]
      # Admin-only fields
      permitted += [:admin_notes, :resolution] if can?(:moderate_feedback)

      # For a stranger the attachment path is an open file-upload endpoint straight into
      # Active Storage, and the selected_element fields let them post arbitrary markup.
      # The bubble also hides those buttons, but THIS is the control that matters —
      # hiding a button stops nobody who is posting the endpoint directly.
      if current_llama_user.nil?
        permitted -= [:selected_element_html, :selected_element_selector,
                      :selected_element_url, :user_id]
        permitted.reject! { |p| p.is_a?(Hash) && p.key?(:attachments) }
        permitted << :user_email
      end

      params.require(:user_feedback).permit(permitted)
    end

    # Submitting is allowed for a signed-in user always, and for a stranger only when the
    # app has opted in. Anything else falls back to the normal identity gate.
    def require_feedback_submitter!
      return if current_llama_user
      return if LlamaBotRails.config.anonymous_feedback_enabled

      require_llama_user!
    end

    # A token is issued with the page and expires in 2 hours. A bot that POSTs this
    # endpoint directly, without ever loading a page, has none. Only enforced when there
    # is no signed-in user, so existing signed-in submissions cannot break.
    #
    # This is the REAL defence. The rate limit below is only a blunt backstop, because
    # Caddy on a Leo box overwrites X-Forwarded-For and every visitor there can share one
    # remote_ip.
    def verify_feedback_submission_token!
      return if current_llama_user

      token = params.dig(:user_feedback, :submission_token)
      verified = begin
        token.present? &&
          Rails.application.message_verifier(:llama_feedback).verified(token).present?
      rescue StandardError
        false
      end
      return if verified

      Rails.logger.info "[LlamaBotRails] feedback submission token rejected from #{request.remote_ip}"
      respond_to do |format|
        format.html { head :forbidden }
        format.json { render json: { success: false, error: "invalid_submission_token" }, status: :forbidden }
      end
    end

    # Blunt backstop only — see verify_feedback_submission_token!. Deliberately not tuned.
    # Rack::Attack is optional, so this degrades to a no-op rather than breaking boot in
    # an app that does not have it.
    def feedback_rate_limit_key
      "llama_feedback:#{request.remote_ip}"
    end
  end
end
