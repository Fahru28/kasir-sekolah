# Stand-ins for the host app's own pages, rendered through layouts/spec_page —
# a layout that never mentions window.llamapressConfig, exactly like the base
# image's application.html.erb and every Leo-generated layout.
# See spec/requests/llama_bot_rails/page_config_injection_spec.rb.
#
# `layout: true` on the :inline renders is required — Rails does not wrap an
# inline render in a layout on its own.
class PagesController < ApplicationController
  layout "spec_page"

  helper_method :current_user

  def show
    render inline: "<p>hello</p>", layout: true
  end

  # A layout that already owns the config (an older client overlay still
  # rendering layouts/_llamapress_page_context).
  def with_config
    render inline: <<~HTML, layout: true
      <script>window.llamapressConfig = { feedbackBubbleEnabled: false };</script>
      <p>hello</p>
    HTML
  end

  # A layout that only TALKS about the config in a comment. It does not own it,
  # so it must still be injected — this is the regression that shipped once.
  def mentions_config
    render inline: <<~HTML, layout: true
      <script>
        // window.llamapressConfig used to be defined here.
      </script>
      <p>hello</p>
    HTML
  end

  # No layout at all, so no <head> to inject into.
  def bare
    render inline: "<p>hello</p>", layout: false
  end

  def not_html
    render json: { ok: true }
  end

  # Host apps expose the visitor one of two ways; ?signed_in=1 turns it on.
  def current_user
    @current_user ||= Struct.new(:id).new(1) if params[:signed_in] == "1"
  end
end
