module LlamaBotRails
  class ApplicationController < ActionController::Base
    before_action :allow_iframe_requests

    # A stale CSRF token must not reach a fetch() caller as a debug page.
    #
    # Leo boxes run RAILS_ENV=development with consider_all_requests_local=true, so an
    # unrescued InvalidAuthenticityToken renders Rails' full HTML error page. When Devise
    # :timeoutable signed a user out from under an open page (SI#342, lohman, 2am local),
    # the feedback widget's POST got that markup back and could only tell the user
    # "Status: 422" while their long, unsent message lived nowhere but the textarea.
    #
    # The 422 is kept deliberately: the client already keys on it. What changes is that a
    # JSON caller now gets something it can act on — refresh the token and retry once, or
    # say plainly that the session expired.
    rescue_from ActionController::InvalidAuthenticityToken do
      respond_to do |format|
        format.json do
          render json: {
            error: "session_expired",
            message: "Your session has expired. Please sign in again."
          }, status: :unprocessable_entity
        end
        format.any do
          redirect_back fallback_location: main_app.root_path,
                        alert: "Session expired. Please try again."
        end
      end
    end

    # The view is a complete HTML document, so it must not be wrapped in the
    # engine layout as well.
    def unauthorized
      render :unauthorized, status: :unauthorized, layout: false
    end

    private

    def allow_iframe_requests
      response.headers.delete('X-Frame-Options')
    end
  end
end
