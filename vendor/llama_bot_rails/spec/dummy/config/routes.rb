Rails.application.routes.draw do
  mount LlamaBotRails::Engine => "/llama_bot_rails"

  # Host-app pages used by the page-config injection specs.
  get "/spec_page",             to: "pages#show"
  get "/spec_page_with_config", to: "pages#with_config"
  get "/spec_page_mentions",    to: "pages#mentions_config"
  get "/spec_page_bare",        to: "pages#bare"
  get "/spec_page_json",        to: "pages#not_html"
  get "/spec_page_devise",      to: "devise_pages#show"

  # Real host apps always have a root; engine views call main_app.root_path (e.g. the
  # feedback navbar), so without this any spec that renders them dies with
  # "undefined method `root_path' for ActionDispatch::Routing::RoutesProxy".
  root to: proc { [200, { "Content-Type" => "text/plain" }, ["dummy root"]] }
end
