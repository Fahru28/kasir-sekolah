require 'net/http'
require 'json'
require 'uri'

module LlamaBotRails
  #This class is responsible for initiating HTTP requests to the FastAPI backend that takes us to LangGraph.
  class LlamaBot
    def self.get_threads
      uri = URI("#{Rails.application.config.llama_bot_rails.llamabot_api_url}/threads")
      response = Net::HTTP.get_response(uri)
      JSON.parse(response.body)
    rescue => e
      Rails.logger.error "Error fetching threads: #{e.message}"
      []
    end

    def self.get_chat_history(thread_id)
      uri = URI("#{Rails.application.config.llama_bot_rails.llamabot_api_url}/chat-history/#{thread_id}")
      response = Net::HTTP.get_response(uri)
      JSON.parse(response.body)
    rescue => e
      Rails.logger.error "Error fetching chat history: #{e.message}"
      []
    end
    
    # Unified Login (Phase 3): redeem a one-time login grant for the `rails_app`
    # audience. The Rails container has no mothership credentials, so we proxy
    # server-to-server through LlamaBot (which holds `.leonardo/instance.json`)
    # via its trusted internal endpoint. LlamaBot forwards to the mothership's
    # `verify_login_grant(token, "rails_app")` and relays the result verbatim.
    #
    # Returns a two-element array [payload, error_code]:
    #   * success  -> [ {"user" => {"guid"=>, "email"=>, "name"=>}, "role"=>, ...}, nil ]
    #   * failure  -> [ nil, "grant_expired" | "grant_used" | "grant_not_found" |
    #                        "bad_audience" | "llamabot_unreachable" | ... ]
    # Never raises — the caller (UnifiedLoginController) must degrade gracefully.
    def self.redeem_rails_grant(token)
      uri = URI("#{Rails.application.config.llama_bot_rails.llamabot_api_url}/internal/redeem_rails_grant")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = 5
      http.read_timeout = 5

      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      request.body = { token: token }.to_json

      response = http.request(request)
      body = JSON.parse(response.body) rescue {}

      if response.code.to_i == 200 && body["success"]
        [body, nil]
      else
        [nil, body["error_code"] || "redeem_failed_#{response.code}"]
      end
    rescue => e
      Rails.logger.error "[LlamaBot] redeem_rails_grant failed: #{e.class}: #{e.message}"
      [nil, "llamabot_unreachable"]
    end

    def self.send_agent_message(agent_params)
      return enum_for(__method__, agent_params) unless block_given?

      uri = URI("#{Rails.application.config.llama_bot_rails.llamabot_api_url}/llamabot-chat-message")
      http = Net::HTTP.new(uri.host, uri.port)
      
      request = Net::HTTP::Post.new(uri)
      
      http.use_ssl = (uri.scheme == "https")

      request['Content-Type'] = 'application/json'
      request.body = agent_params.to_json

      # Stream the response instead of buffering it
      http.request(request) do |response|
        if response.code.to_i == 200
          buffer = ''
          
          response.read_body do |chunk|
            buffer += chunk
            
            # Process complete lines (ended with \n)
            while buffer.include?("\n")
              line, buffer = buffer.split("\n", 2)
              if line.strip.present?
                begin
                  yield JSON.parse(line)
                rescue JSON::ParserError => e
                  Rails.logger.error "Parse error: #{e.message}"
                end
              end
            end
          end
          
          # Process any remaining data in buffer
          if buffer.strip.present?
            begin
              yield JSON.parse(buffer)
            rescue JSON::ParserError => e
              Rails.logger.error "Final buffer parse error: #{e.message}"
            end
          end
        end
      end
    rescue => e
      Rails.logger.error "Error sending agent message: #{e.message}"
      { error: e.message }
    end
  end
end