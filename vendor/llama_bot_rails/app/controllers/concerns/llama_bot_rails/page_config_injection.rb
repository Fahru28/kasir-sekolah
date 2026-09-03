# frozen_string_literal: true

module LlamaBotRails
  # Puts `window.llamapressConfig` on every HTML page the host app renders, no
  # matter which layout rendered it.
  #
  # It used to live in a single layout partial (layouts/_llamapress_page_context),
  # which only ever existed in one client overlay and was only rendered by that
  # overlay's application.html.erb. Every other layout — the prototypes layout, a
  # Leo-generated one, an admin shell, and the base image's OWN application
  # layout — shipped without it, so the feedback bubble (which refuses to draw
  # unless `feedbackBubbleEnabled && userLoggedIn`) silently never appeared.
  #
  # An after_action is the layout-proof place for this: it runs for every
  # controller and nobody writing the next layout has to remember it. Lives in
  # the ENGINE, not the base image's app/, because client overlays volume-mount
  # over app/ — anything there would vanish downstream.
  #
  # If the rendered body already assigns window.llamapressConfig — an older
  # overlay still rendering the partial — we leave it alone. So this is purely
  # additive and can never double-define.
  #
  # Opt out per controller:
  #
  #   skip_llama_page_config             # whole controller
  #   skip_llama_page_config only: :raw
  module PageConfigInjection
    extend ActiveSupport::Concern

    # Matches the opening <head>, with or without attributes. We insert straight
    # after it so the assignment runs before any deferred module (importmap
    # ships feedback_bubble.js as one) gets to look at it.
    HEAD_TAG = /<head\b[^>]*>/i

    # "Does this page already define the config itself?" Deliberately an
    # ASSIGNMENT, not a bare mention: a layout that merely talks about
    # window.llamapressConfig in a comment must not switch the injection off.
    # (It did, the first time — the replacement comment left behind in
    # Leonardo's _llamapress_page_context partial was enough to suppress it.)
    EXISTING_CONFIG = /window\.llamapressConfig\s*=[^=]/

    # Belt and braces: what the config should be if the engine is mounted
    # somewhere we cannot resolve.
    DEFAULT_RELEASES_PATH = "/llama_bot/releases"

    included do
      class_attribute :llama_page_config_enabled, instance_writer: false, default: true

      after_action :llama_inject_page_config
    end

    class_methods do
      def skip_llama_page_config(**options)
        skip_after_action :llama_inject_page_config, **options, raise: false
        self.llama_page_config_enabled = false if options.empty?
      end
    end

    private

    # Wrapped whole: a failure here must never fail the request the host app is
    # actually trying to serve.
    def llama_inject_page_config
      return unless llama_page_config_enabled
      return unless LlamaBotRails.config.inject_page_config
      return unless llama_page_config_injectable?

      body = response.body
      return if body.blank?
      return if body.match?(EXISTING_CONFIG)

      head = body[HEAD_TAG]
      return if head.nil?

      response.body = body.sub(head, "#{head}\n#{llama_page_config_script}")
    rescue StandardError => e
      Rails.logger.debug { "[LlamaBotRails] page config injection skipped: #{e.class}: #{e.message}" }
    end

    # Only minted when anonymous submissions are actually enabled: there is no reason to
    # put a credential on every page of every app that has not opted in.
    def llama_feedback_submission_token
      return nil unless LlamaBotRails.config.anonymous_feedback_enabled

      Rails.application.message_verifier(:llama_feedback).generate(
        { issued_at: Time.current.to_i }, expires_in: 2.hours
      )
    rescue StandardError => e
      Rails.logger.debug { "[LlamaBotRails] feedback token mint skipped: #{e.class}: #{e.message}" }
      nil
    end

    def llama_page_config_injectable?
      return false unless response.media_type == "text/html"
      return false unless (200..299).cover?(response.status)
      # Streamed and file responses have no rewritable String body.
      response.body.is_a?(String)
    rescue StandardError
      false
    end

    def llama_page_config_script
      config = {
        feedbackBubbleEnabled: !!LlamaBotRails.config.feedback_bubble_enabled,
        userLoggedIn: llama_page_config_user_signed_in?,
        anonymousFeedbackEnabled: !!LlamaBotRails.config.anonymous_feedback_enabled,
        # Issued WITH the page, so a bot that never loads one cannot submit. The
        # controller only enforces it for signed-out submissions.
        feedbackSubmissionToken: llama_feedback_submission_token,
        appVersion: LlamaBotRails.app_version,
        releasesUrl: llama_page_config_releases_path
      }

      # json_escape turns < > & into \uXXXX, so no value can close the <script>.
      "<script>window.llamapressConfig = #{ERB::Util.json_escape(config.to_json)};</script>"
    end

    def llama_page_config_user_signed_in?
      if respond_to?(:user_signed_in?, true)
        !!user_signed_in?
      elsif respond_to?(:current_user, true)
        current_user.present?
      else
        false
      end
    rescue StandardError
      false
    end

    def llama_page_config_releases_path
      LlamaBotRails::Engine.routes.url_helpers.releases_path
    rescue StandardError
      DEFAULT_RELEASES_PATH
    end
  end
end
