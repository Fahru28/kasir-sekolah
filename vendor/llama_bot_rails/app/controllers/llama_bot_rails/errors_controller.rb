require "llama_bot_rails/error_log"

module LlamaBotRails
  # Serves the app's recent crashes to LlamaBot, which polls this once per model
  # call so Leo can notice mid-turn that the code it just wrote broke the app.
  # See docs/dev/rails_auto_recovery.md in the LlamaBot repo.
  #
  # Agent-only. `llama_bot_allow :index` makes check_agent_authentication reject
  # anything that is not a signed LlamaBot request — backtraces name file paths
  # and line numbers, so this must never be readable by whoever happens to hit
  # the URL.
  class ErrorsController < ActionController::Base
    include LlamaBotRails::AgentAuth
    include LlamaBotRails::ControllerExtensions

    llama_bot_allow :index

    skip_before_action :verify_authenticity_token, raise: false
    before_action :check_agent_authentication, unless: :box_feed_request?

    # GET /llama_bot/errors[?since=<seq>][?within=<seconds>]
    #
    # Three modes, in precedence order:
    #
    #   since=<seq>       delta fetch — everything after a cursor the caller holds.
    #                     The steady state once a turn is running.
    #   within=<seconds>  everything that crashed recently. How a turn arms itself
    #                     when the app is ALREADY broken: the user is staring at
    #                     the error page asking for a fix, so no *new* crash is
    #                     coming and a cursor alone would stay silent forever.
    #   neither           cursor probe: where the log stands, no entries.
    def index
      cursor = numeric_param(params[:since])
      window = numeric_param(params[:within])

      errors =
        if cursor
          LlamaBotRails::ErrorLog.since(cursor)
        elsif window
          LlamaBotRails::ErrorLog.within(window)
        else
          []
        end

      render json: { seq: LlamaBotRails::ErrorLog.latest_seq, errors: errors }
    end

    private

    # True only for a correctly-signed box-internal request. Anything else — a
    # wrong token, the right token under the wrong scheme, a box with no shared
    # secret — falls through to the agent-token check rather than being let in.
    def box_feed_request?
      header = request.headers["Authorization"].to_s
      scheme, token = header.split(" ", 2)
      return false unless scheme == LlamaBotRails::ErrorFeedToken::SCHEME

      LlamaBotRails::ErrorFeedToken.valid?(token)
    end

    # Nil (probe) for anything that is not a plain integer. A garbled cursor
    # must not be read as 0 — that would replay the whole ring into a turn.
    def numeric_param(raw)
      value = raw.to_s.strip
      return nil unless value.match?(/\A\d+\z/)

      value.to_i
    end
  end
end
