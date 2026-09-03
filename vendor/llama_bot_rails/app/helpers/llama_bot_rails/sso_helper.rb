require "cgi"

module LlamaBotRails
  # Unified Login — the "Sign in with your LlamaPress.ai account" SSO entry point.
  #
  # Platform-owned: shipping this in the gem keeps it on the right side of the
  # platform/user boundary — it survives host-app view edits and the Leonardo
  # `rails/app` overlay that shadows the base skeleton.
  #
  # Render the CTA from a host Devise sign-in view with:
  #   <%= LlamaBotRails::SsoHelper.cta_html %>
  #
  # cta_html is a class method (NOT a view partial) on purpose: an engine's view
  # PATHS load lazily in development mode, so a `render "llama_bot_rails/..."` is
  # not resolvable for the first several requests after a cold boot (deploy /
  # restart / wake) — the CTA would be missing until the app warms. Class/helper
  # methods autoload from the very first request, so building the HTML here makes
  # the CTA present immediately, with no warm-up race.
  module SsoHelper
    module_function

    # Build the LlamaPress.ai SSO sign-in URL for this instance, or nil when the
    # box isn't mothership-managed (self-hosted apps show the stock form only).
    #
    # The values are written to the instance's .env by the mothership. A plain
    # link needs no secret, so MOTHERSHIP_API_TOKEN is deliberately NOT read here
    # — keeping the mothership token out of the Rails container is the whole point
    # of Unified Login.
    def sign_in_url(
      mothership_url: ENV["MOTHERSHIP_URL"],
      instance_name: ENV["MOTHERSHIP_INSTANCE_NAME"]
    )
      mothership_url = mothership_url.to_s.strip
      instance_name = instance_name.to_s.strip
      return nil if mothership_url.empty? || instance_name.empty?

      "#{mothership_url.chomp('/')}/sso/leo/#{instance_name}"
    end

    # The CTA markup as an html_safe string, or "" when the box isn't
    # mothership-managed. Built without a view context (no link_to) so it's
    # callable from the first cold-boot request — see the module note above.
    #
    # Behavior mirrors what the view partial rendered: target="_top", and a
    # frame-detect script that appends surface=rails_app when the page is NOT in
    # the chat's app-preview iframe (window.self === window.top) so a standalone
    # Rails visit lands back on Rails after login; framed stays chat. The URL is
    # HTML-escaped into the href.
    def cta_html
      url = sign_in_url
      return "".html_safe if url.blank?

      esc = CGI.escapeHTML(url)
      <<~HTML.html_safe
        <div class="max-w-md mx-auto mt-8">
          <a id="lp-sso-cta" target="_top" href="#{esc}" class="block w-full text-center rounded-lg bg-indigo-600 py-3 px-4 text-white font-semibold shadow-md hover:bg-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-400 focus:ring-opacity-75">Sign in with your LlamaPress.ai account</a>
          <div class="mt-6 flex items-center max-w-md mx-auto">
            <div class="flex-grow border-t border-gray-200"></div>
            <span class="mx-3 text-sm text-gray-400">or sign in with a password</span>
            <div class="flex-grow border-t border-gray-200"></div>
          </div>
        </div>
        <script>
          (function () {
            if (window.self === window.top) {
              var a = document.getElementById("lp-sso-cta");
              if (a) a.href += (a.href.indexOf("?") === -1 ? "?" : "&") + "surface=rails_app";
            }
          })();
        </script>
      HTML
    end
  end
end
