module LlamaBotRails
  class UsersController < ApplicationController
    include Authorizable

    # Stays behind sign-in even while the rest of the app is open. This endpoint
    # returns the address book, and it only ever serves @mention autocomplete
    # inside already-signed-in screens, so opening it would leak every user's
    # email address to anonymous visitors and buy nothing.
    before_action :require_llama_user!

    # GET /users/search?q=query
    def search
      query = params[:q].to_s.downcase.strip
      users = load_available_users

      if query.present?
        users = users.select { |u| u.email.to_s.downcase.include?(query) }
      end

      # Exclude current user from results
      users = users.reject { |u| u.id == current_llama_user&.id }

      # Limit results
      users = users.first(10)

      render json: users.map { |u| { id: u.id, email: u.email } }
    end

    private

    def load_available_users
      if defined?(Devise)
        default_scope = Devise.default_scope
        user_class = Devise.mappings[default_scope].to
        user_class.all.order(:email)
      else
        []
      end
    end
  end
end
