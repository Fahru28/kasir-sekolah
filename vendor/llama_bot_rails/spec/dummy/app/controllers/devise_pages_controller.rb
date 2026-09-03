# The Devise shape: user_signed_in? is preferred over current_user when a host
# app exposes both. See spec/requests/llama_bot_rails/page_config_injection_spec.rb.
class DevisePagesController < PagesController
  def user_signed_in?
    params[:signed_in] == "1"
  end

  # Deliberately unhelpful, to prove user_signed_in? is what gets asked.
  def current_user
    raise "current_user should not be consulted when user_signed_in? exists"
  end
end
