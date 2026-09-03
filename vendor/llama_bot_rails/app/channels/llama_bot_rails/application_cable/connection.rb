# llama_bot_rails/app/channels/llama_bot_rails/application_cable/connection.rb
module LlamaBotRails
  module ApplicationCable
    class Connection < ActionCable::Connection::Base
      identified_by :uuid, :current_user_id

      def connect
        self.uuid = SecureRandom.uuid

        # Try to get current user for authenticated channels
        user = LlamaBotRails.current_user_resolver&.call(env)
        self.current_user_id = user&.id

        Rails.logger.info "[LlamaBotRails::Connection] Connected: uuid=#{uuid}, user_id=#{current_user_id}"
      end
    end
  end
end
  