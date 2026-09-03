module LlamaBotRails
    module AgentAuth
      extend ActiveSupport::Concern
      AUTH_SCHEME = "LlamaBot"
      # Structured error codes for authentication failures
      AUTH_ERRORS = {
        missing_auth_header: "LLAMA_AUTH_001",
        invalid_auth_scheme: "LLAMA_AUTH_002",
        missing_token: "LLAMA_AUTH_003",
        invalid_signature: "LLAMA_AUTH_004",
        expired_token: "LLAMA_AUTH_005",
        user_not_found: "LLAMA_AUTH_006",
        sign_in_failed: "LLAMA_AUTH_007",
        action_not_whitelisted: "LLAMA_AUTH_008",
        warden_auth_failed: "LLAMA_AUTH_009"
      }.freeze
  
      included do
        # Add before_action filter to automatically check agent authentication for LlamaBot requests

        if self < ActionController::Base
          before_action :check_agent_authentication, if: :should_check_agent_auth?
        end
        
        # ------------------------------------------------------------------
        # 1) For every Devise scope, alias authenticate_<scope>! so it now
        #    accepts *either* a logged-in browser session OR a valid agent
        #    token. Existing before/skip filters keep working.
        # ------------------------------------------------------------------
        if defined?(Devise)
          Devise.mappings.keys.each do |scope|
            scope_filter = :"authenticate_#{scope}!"
  
            # Next line is a no-op if the method wasn’t already defined.
            alias_method scope_filter, :authenticate_user_or_agent! \
              if method_defined?(scope_filter)
  
            # Emit a gentle nudge during development
            define_method(scope_filter) do |*args|
              Rails.logger.warn(
                "#{scope_filter} is now handled by LlamaBotRails::AgentAuth "\
                "and will be removed in a future version. "\
                "Use authenticate_user_or_agent! instead."
              )
              authenticate_user_or_agent!(*args)
            end
          end
        end
  
        # ------------------------------------------------------------------
        # 2) If Devise isn’t loaded at all, fall back to one alias so apps
        #    that had authenticate_user! manually defined don’t break.
        # ------------------------------------------------------------------
        unless defined?(Devise)
          # Store the original method if it exists
          original_authenticate_user = if method_defined?(:authenticate_user!)
            instance_method(:authenticate_user!)
          else
            nil
          end
          
          # Define the new method that calls authenticate_user_or_agent!
          define_method(:authenticate_user!) do |*args|
            authenticate_user_or_agent!(*args)
          end
        end
      end
  
      # --------------------------------------------------------------------
      # Public helper: true if the request carries a *valid* agent token
      # --------------------------------------------------------------------
      def should_check_agent_auth?
        # Skip agent authentication entirely if a Devise user is already signed in
        return false if devise_user_signed_in?
        
        # Only check for LlamaBot requests if no Devise user is signed in
        llama_bot_request?
      end

      def llama_bot_request?
        validation = validate_llama_bot_token
        validation[:valid]
      end

      # Returns detailed validation result for the LlamaBot token
      # @return [Hash] { valid: Boolean, error_code: String|nil, error_details: Hash|nil, token_data: Hash|nil }
      def validate_llama_bot_token
        unless request&.headers
          return { valid: false, error_code: AUTH_ERRORS[:missing_auth_header], error_details: { reason: "No request headers available" } }
        end

        auth_header = request.headers["Authorization"]

        unless auth_header.present?
          return {
            valid: false,
            error_code: AUTH_ERRORS[:missing_auth_header],
            error_details: {
              reason: "Authorization header is missing",
              expected_format: "Authorization: LlamaBot <signed-token>",
              headers_present: request.headers.to_h.keys.select { |k| k.to_s.start_with?("HTTP_") }.map { |k| k.to_s.sub("HTTP_", "") }
            }
          }
        end

        scheme, token = auth_header.split(" ", 2)
        Rails.logger.debug("[LlamaBot] auth header = #{scheme.inspect} #{token&.slice(0,8)}…")

        unless scheme == AUTH_SCHEME
          return {
            valid: false,
            error_code: AUTH_ERRORS[:invalid_auth_scheme],
            error_details: {
              reason: "Invalid authorization scheme",
              received_scheme: scheme,
              expected_scheme: AUTH_SCHEME,
              hint: "Ensure the Authorization header uses 'LlamaBot' scheme, not '#{scheme}'"
            }
          }
        end

        unless token.present?
          return {
            valid: false,
            error_code: AUTH_ERRORS[:missing_token],
            error_details: {
              reason: "Token is missing after scheme",
              received_header: "#{scheme} <empty>",
              expected_format: "LlamaBot <signed-token>"
            }
          }
        end

        begin
          token_data = Rails.application.message_verifier(:llamabot_ws).verify(token)
          { valid: true, token_data: token_data }
        rescue ActiveSupport::MessageVerifier::InvalidSignature => e
          # Try to decode without verification to get more debug info
          token_debug_info = extract_token_debug_info(token)

          {
            valid: false,
            error_code: token_debug_info[:expired] ? AUTH_ERRORS[:expired_token] : AUTH_ERRORS[:invalid_signature],
            error_details: {
              reason: token_debug_info[:expired] ? "Token has expired" : "Token signature verification failed",
              token_prefix: token&.slice(0, 20),
              token_length: token&.length,
              verifier_purpose: :llamabot_ws,
              exception_class: e.class.name,
              exception_message: e.message,
              possible_causes: token_debug_info[:expired] ?
                ["Token TTL exceeded (check expires_in setting)", "Clock skew between Rails app and LlamaBot backend", "Token was generated too long ago"] :
                ["secret_key_base mismatch between token generator and verifier", "Token was tampered with", "Token was generated for a different Rails app", "Token encoding/decoding issue"],
              debug_info: token_debug_info
            }
          }
        end
      end

      private

      # Attempts to extract debug info from a token without full verification
      def extract_token_debug_info(token)
        info = { expired: false, decoded: false }

        begin
          # Try to decode the token structure (Base64) without signature verification
          # MessageVerifier tokens are Base64 encoded with format: data--signature
          if token&.include?("--")
            data_part, _signature = token.split("--", 2)
            if data_part
              begin
                decoded = Base64.strict_decode64(data_part)
                # Try to parse as JSON or Marshal
                begin
                  parsed = JSON.parse(decoded)
                  info[:decoded] = true
                  info[:payload_type] = "JSON"
                  # Check for expiration in _rails metadata
                  if parsed.is_a?(Hash)
                    if parsed["_rails"] && parsed["_rails"]["exp"]
                      exp_time = Time.parse(parsed["_rails"]["exp"]) rescue nil
                      if exp_time && exp_time < Time.current
                        info[:expired] = true
                        info[:expired_at] = parsed["_rails"]["exp"]
                        info[:expired_ago] = "#{((Time.current - exp_time) / 60).round(1)} minutes ago"
                      end
                    end
                    info[:has_session_id] = parsed["session_id"].present? || (parsed["_rails"] && parsed["_rails"]["message"] && parsed["_rails"]["message"]["session_id"]).present?
                    info[:has_user_id] = parsed["user_id"].present? || (parsed["_rails"] && parsed["_rails"]["message"] && parsed["_rails"]["message"]["user_id"]).present?
                  end
                rescue JSON::ParserError
                  # Try Marshal format (older Rails)
                  begin
                    marshaled = Marshal.load(decoded)
                    info[:decoded] = true
                    info[:payload_type] = "Marshal"
                  rescue
                    info[:payload_type] = "Unknown"
                  end
                end
              rescue ArgumentError
                info[:base64_valid] = false
              end
            end
          else
            info[:token_format] = "Invalid (missing -- separator)"
          end
        rescue => e
          info[:decode_error] = e.message
        end

        info
      end

      # --------------------------------------------------------------------
      # Automatic check for LlamaBot requests - called by before_action filter
      # --------------------------------------------------------------------
      def check_agent_authentication
        # Check if this controller has LlamaBot-aware actions
        has_permitted_actions = self.class.respond_to?(:llama_bot_permitted_actions)
        
        # Skip if controller doesn't use llama_bot_allow at all
        return unless has_permitted_actions
        
        is_llama_request = llama_bot_request?
        action_is_whitelisted = self.class.llama_bot_permitted_actions.include?(action_name)
        
        if is_llama_request
          # If it's a LlamaBot request, only allow whitelisted actions
          unless action_is_whitelisted
            Rails.logger.warn("[LlamaBot] Action '#{action_name}' isn't white-listed for LlamaBot. To fix this, add `llama_bot_allow :#{action_name}` in your controller.")
            render json: { error: "Action '#{action_name}' isn't white-listed for LlamaBot. To fix this, add `llama_bot_allow :#{action_name}` in your controller." }, status: :forbidden
            return
          end
          Rails.logger.debug("[[LlamaBot Debug]] Valid LlamaBot request for action '#{action_name}'")
        elsif action_is_whitelisted
          # If action requires LlamaBot auth but request isn't a LlamaBot request, reject it
          Rails.logger.warn("[LlamaBot] Action '#{action_name}' requires LlamaBot authentication, but request is not a valid LlamaBot request.")
          render json: { error: "Action '#{action_name}' requires LlamaBot authentication" }, status: :forbidden
          return
        end
        
        # All other cases: non-LlamaBot requests to non-whitelisted actions are allowed
      end

      # --------------------------------------------------------------------
      # Unified guard — browser OR agent
      # --------------------------------------------------------------------
      def devise_user_signed_in?
        return false unless defined?(Devise)
        return false unless request&.env
        request.env["warden"]&.authenticated?
      end
  
      def authenticate_user_or_agent!(*)
        return if devise_user_signed_in?  # any logged-in Devise scope

        # Validate the LlamaBot token with detailed error info
        validation = validate_llama_bot_token

        if validation[:valid]
          token_data = validation[:token_data]

          allowed = self.class.respond_to?(:llama_bot_permitted_actions) &&
                  self.class.llama_bot_permitted_actions.include?(action_name)

          if allowed
            user_id = token_data[:user_id] || token_data["user_id"]
            user_object = LlamaBotRails.user_resolver.call(user_id)

            if user_object.nil?
              render_auth_error(
                AUTH_ERRORS[:user_not_found],
                "User not found for the provided token",
                {
                  user_id: user_id,
                  user_id_present: user_id.present?,
                  resolver_class: LlamaBotRails.user_resolver.class.name,
                  hint: "Ensure user_resolver is configured correctly and the user exists"
                }
              )
              return false
            end

            unless LlamaBotRails.sign_in_method.call(request.env, user_object)
              render_auth_error(
                AUTH_ERRORS[:sign_in_failed],
                "Failed to sign in user via LlamaBot token",
                {
                  user_id: user_id,
                  user_class: user_object.class.name,
                  sign_in_method_class: LlamaBotRails.sign_in_method.class.name,
                  hint: "Check sign_in_method configuration and ensure it returns truthy on success"
                }
              )
              return false
            end

            return  # ✅ token + allow-listed action + user found and set properly for rack environment
          else
            # ❌ auth token is valid, but the attempted controller action is not added to the whitelist.
            Rails.logger.warn("[LlamaBot] Action '#{action_name}' isn't white-listed for LlamaBot. To fix this, include LlamaBotRails::ControllerExtensions and add `llama_bot_allow :method` in your controller.")
            render json: { error: "Action '#{action_name}' isn't white-listed for LlamaBot. To fix this, include LlamaBotRails::ControllerExtensions and add `llama_bot_allow :method` in your controller." }, status: :forbidden
            return false
          end
        elsif validation[:error_code]
          # Token validation failed - provide detailed error info
          render_auth_error(
            validation[:error_code],
            validation[:error_details][:reason],
            validation[:error_details]
          )
          return false
        end

        # Neither path worked — fall back to Devise's normal behaviour and let Devise handle 401
        if defined?(Devise) && request&.env
          begin
            request.env["warden"].authenticate!  # 401 or redirect
          rescue Warden::NotAuthenticated => e
            render_auth_error(
              AUTH_ERRORS[:warden_auth_failed],
              "Warden authentication failed",
              {
                warden_message: e.message,
                hint: "No valid session or LlamaBot token found"
              }
            )
          end
        else
          render_auth_error(
            AUTH_ERRORS[:missing_auth_header],
            "No authentication method available",
            {
              devise_available: defined?(Devise).present?,
              request_env_present: request&.env.present?,
              hint: "Include a valid LlamaBot token in the Authorization header"
            }
          )
        end
      end

      # Renders a detailed 401 unauthorized error with structured debugging info
      def render_auth_error(error_code, message, details = {})
        error_payload = build_auth_error_payload(error_code, message, details)

        # Log the detailed error
        log_auth_failure(error_payload)

        # Render the response
        render json: error_payload, status: :unauthorized
      end

      # Builds a structured error payload for authentication failures
      def build_auth_error_payload(error_code, message, details = {})
        {
          error: "Unauthorized",
          error_code: error_code,
          message: message,
          details: details.except(:hint),
          hint: details[:hint],
          request_info: {
            controller: self.class.name,
            action: action_name,
            method: request.method,
            path: request.path,
            remote_ip: request.remote_ip,
            request_id: request.request_id
          },
          timestamp: Time.current.iso8601,
          documentation_url: "https://github.com/your-org/llama_bot_rails#authentication-errors"
        }
      end

      # Logs authentication failure with structured output
      def log_auth_failure(error_payload)
        Rails.logger.error(
          "[LlamaBot Auth Failure] " \
          "code=#{error_payload[:error_code]} " \
          "message=\"#{error_payload[:message]}\" " \
          "controller=#{error_payload[:request_info][:controller]} " \
          "action=#{error_payload[:request_info][:action]} " \
          "path=#{error_payload[:request_info][:path]} " \
          "ip=#{error_payload[:request_info][:remote_ip]} " \
          "request_id=#{error_payload[:request_info][:request_id]}"
        )

        # Log additional details at debug level for deeper investigation
        Rails.logger.debug("[LlamaBot Auth Failure Details] #{error_payload[:details].to_json}")

        if error_payload[:hint]
          Rails.logger.info("[LlamaBot Auth Hint] #{error_payload[:hint]}")
        end
      end
    end
  end
  