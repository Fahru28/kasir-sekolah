require 'rails_helper'

RSpec.describe LlamaBotRails::AgentAuth do
  let(:controller_class) do
    Class.new(ActionController::Base) do
      include LlamaBotRails::AgentAuth
      include LlamaBotRails::ControllerExtensions

      llama_bot_allow :allowed_action

      def allowed_action
        render json: { message: 'success' }
      end

      def not_allowed_action
        render json: { message: 'should not reach here' }
      end
    end
  end

  let(:controller) { controller_class.new }
  let(:request) { double('request') }
  let(:headers) { {} }
  let(:env) { {} }

  before do
    allow(controller).to receive(:request).and_return(request)
    allow(request).to receive(:headers).and_return(headers)
    allow(request).to receive(:env).and_return(env)
    allow(request).to receive(:method).and_return('GET')
    allow(request).to receive(:path).and_return('/test')
    allow(request).to receive(:remote_ip).and_return('127.0.0.1')
    allow(request).to receive(:request_id).and_return('test-request-id')
    allow(controller).to receive(:action_name).and_return('allowed_action')
    allow(controller).to receive(:render)
    allow(controller).to receive(:head)

    # Clear any existing user resolvers
    LlamaBotRails.user_resolver = nil
    LlamaBotRails.current_user_resolver = nil
    LlamaBotRails.sign_in_method = nil
  end

  describe '#llama_bot_request?' do
    context 'with no authorization header' do
      it 'returns false' do
        expect(controller.send(:llama_bot_request?)).to be false
      end
    end

    context 'with incorrect scheme' do
      before do
        headers['Authorization'] = 'Bearer some-token'
      end

      it 'returns false' do
        expect(controller.send(:llama_bot_request?)).to be false
      end
    end

    context 'with correct scheme but invalid token' do
      before do
        headers['Authorization'] = 'LlamaBot invalid-token'
      end

      it 'returns false due to verification failure' do
        allow(Rails.application.message_verifier(:llamabot_ws))
          .to receive(:verify)
          .and_raise(ActiveSupport::MessageVerifier::InvalidSignature)
        
        expect(controller.send(:llama_bot_request?)).to be false
      end
    end

    context 'with valid LlamaBot token' do
      let(:valid_token) { 'valid-token' }
      
      before do
        headers['Authorization'] = "LlamaBot #{valid_token}"
        allow(Rails.application.message_verifier(:llamabot_ws))
          .to receive(:verify)
          .with(valid_token)
          .and_return({ session_id: 'test', user_id: 123 })
      end

      it 'returns true' do
        expect(controller.send(:llama_bot_request?)).to be true
      end
    end
  end

  describe '#check_agent_authentication' do
    let(:valid_token) { 'valid-token' }
    let(:token_data) { { session_id: 'test-session', user_id: 123 } }

    before do
      headers['Authorization'] = "LlamaBot #{valid_token}"
      allow(Rails.application.message_verifier(:llamabot_ws))
        .to receive(:verify)
        .with(valid_token)
        .and_return(token_data)
    end

    context 'when action is not whitelisted and no valid LlamaBot request' do
      before do
        # Make action_name return something not in the allowed list
        allow(controller).to receive(:action_name).and_return('not_allowed_action')
        headers.clear
      end

      it 'allows the request to proceed normally' do
        expect(controller).not_to receive(:render)
        controller.send(:check_agent_authentication)
      end
    end

    context 'when action requires LlamaBot auth but is not a valid LlamaBot request' do
      before do
        # Make action_name return something in the allowed list
        allow(controller).to receive(:action_name).and_return('allowed_action')
        headers.clear
      end

      it 'renders forbidden error' do
        expect(controller).to receive(:render).with(
          json: { error: "Action 'allowed_action' requires LlamaBot authentication" },
          status: :forbidden
        )
        
        controller.send(:check_agent_authentication)
      end
    end

    context 'when action is whitelisted' do
      it 'proceeds without error' do
        expect(controller).not_to receive(:render)
        controller.send(:check_agent_authentication)
      end
    end

    context 'when LlamaBot request is made to non-whitelisted action' do
      before do
        # Make llama_bot_request? return true but action not whitelisted
        allow(controller).to receive(:llama_bot_request?).and_return(true)
        allow(controller).to receive(:action_name).and_return('not_allowed_action')
      end

      it 'renders forbidden error' do
        expect(controller).to receive(:render).with(
          json: { error: "Action 'not_allowed_action' isn't white-listed for LlamaBot. To fix this, add `llama_bot_allow :not_allowed_action` in your controller." },
          status: :forbidden
        )
        controller.send(:check_agent_authentication)
      end
    end

    context 'when token verification passes' do
      before do
        # Make llama_bot_request? return true and action whitelisted
        allow(controller).to receive(:llama_bot_request?).and_return(true)
        allow(controller).to receive(:action_name).and_return('allowed_action')
      end

      it 'logs success and continues processing' do
        expect(Rails.logger).to receive(:debug).with(match(/Valid LlamaBot request for action/))
        controller.send(:check_agent_authentication)
      end
    end
  end

  describe '#authenticate_user_or_agent!' do
    let(:valid_token) { 'valid-token' }
    let(:user_id) { 123 }
    let(:token_data) { { session_id: 'test-session', user_id: user_id } }
    let(:mock_user) { double('User', id: user_id) }

    before do
      headers['Authorization'] = "LlamaBot #{valid_token}"
      allow(Rails.application.message_verifier(:llamabot_ws))
        .to receive(:verify)
        .with(valid_token)
        .and_return(token_data)
    end

    context 'when user is already signed in via Devise' do
      before do
        allow(controller).to receive(:devise_user_signed_in?).and_return(true)
      end

      it 'returns early without checking agent auth' do
        expect(controller).not_to receive(:llama_bot_request?)
        controller.send(:authenticate_user_or_agent!)
      end
    end

    context 'when user is not signed in but valid agent request' do
      before do
        allow(controller).to receive(:devise_user_signed_in?).and_return(false)
        
        # Set up user resolver
        LlamaBotRails.user_resolver = ->(id) { mock_user if id == user_id }
        LlamaBotRails.sign_in_method = ->(env, user) { true }
      end

      it 'resolves user and signs them in' do
        expect(LlamaBotRails.user_resolver).to receive(:call).with(user_id).and_return(mock_user)
        expect(LlamaBotRails.sign_in_method).to receive(:call).with(env, mock_user).and_return(true)
        
        controller.send(:authenticate_user_or_agent!)
      end

      context 'when user cannot be found' do
        before do
          LlamaBotRails.user_resolver = ->(id) { nil }
        end

        it 'renders unauthorized with detailed user_not_found error' do
          expect(controller).to receive(:render).with(
            hash_including(
              json: hash_including(
                error: "Unauthorized",
                error_code: "LLAMA_AUTH_006",
                message: "User not found for the provided token"
              ),
              status: :unauthorized
            )
          )
          controller.send(:authenticate_user_or_agent!)
        end

        it 'logs the authentication failure' do
          # Allow render to be called
          allow(controller).to receive(:render)
          # Allow other debug logs
          allow(Rails.logger).to receive(:debug)

          expect(Rails.logger).to receive(:error).with(/\[LlamaBot Auth Failure\].*LLAMA_AUTH_006/)
          expect(Rails.logger).to receive(:info).with(/\[LlamaBot Auth Hint\]/)
          controller.send(:authenticate_user_or_agent!)
        end
      end

      context 'when sign in fails' do
        before do
          LlamaBotRails.sign_in_method = ->(env, user) { false }
        end

        it 'renders unauthorized with detailed sign_in_failed error' do
          expect(controller).to receive(:render).with(
            hash_including(
              json: hash_including(
                error: "Unauthorized",
                error_code: "LLAMA_AUTH_007",
                message: "Failed to sign in user via LlamaBot token"
              ),
              status: :unauthorized
            )
          )
          controller.send(:authenticate_user_or_agent!)
        end

        it 'logs the authentication failure with structured output' do
          # Allow render to be called
          allow(controller).to receive(:render)
          # Allow other debug logs
          allow(Rails.logger).to receive(:debug)

          expect(Rails.logger).to receive(:error).with(/\[LlamaBot Auth Failure\].*LLAMA_AUTH_007/)
          expect(Rails.logger).to receive(:info).with(/\[LlamaBot Auth Hint\]/)
          controller.send(:authenticate_user_or_agent!)
        end
      end

      context 'when action is not whitelisted' do
        before do
          allow(controller).to receive(:action_name).and_return('not_allowed_action')
        end

        it 'renders forbidden error' do
          expect(controller).to receive(:render).with(
            json: { error: match(/isn't white-listed/) },
            status: :forbidden
          )
          
          controller.send(:authenticate_user_or_agent!)
        end
      end
    end

    context 'when neither Devise nor agent auth succeeds' do
      before do
        allow(controller).to receive(:devise_user_signed_in?).and_return(false)

        # Clear auth header so validate_llama_bot_token returns invalid
        headers.clear

        # Mock Devise environment
        warden = double('warden')
        env['warden'] = warden

        # Mock Devise constant being defined
        unless defined?(Devise)
          stub_const('Devise', double('Devise'))
        end
      end

      it 'renders unauthorized with missing auth header error when no token provided' do
        # With no auth header, the code will render the missing_auth_header error
        expect(controller).to receive(:render).with(
          hash_including(
            json: hash_including(
              error: "Unauthorized",
              error_code: "LLAMA_AUTH_001",
              message: "Authorization header is missing"
            ),
            status: :unauthorized
          )
        )
        controller.send(:authenticate_user_or_agent!)
      end

      context 'when Devise is not available' do
        before do
          env.clear # Remove warden
          # Also undefine Devise for this test
          hide_const('Devise') if defined?(Devise)
        end

        it 'renders unauthorized with detailed error including debugging info' do
          expect(controller).to receive(:render).with(
            hash_including(
              json: hash_including(
                error: "Unauthorized",
                error_code: "LLAMA_AUTH_001",
                message: "Authorization header is missing"
              ),
              status: :unauthorized
            )
          )
          controller.send(:authenticate_user_or_agent!)
        end
      end
    end
  end

  describe '#devise_user_signed_in?' do
    context 'when Devise is not defined' do
      before do
        hide_const('Devise')
      end

      it 'returns false' do
        expect(controller.send(:devise_user_signed_in?)).to be false
      end
    end

    context 'when request env is not available' do
      before do
        allow(controller).to receive(:request).and_return(nil)
      end

      it 'returns false' do
        expect(controller.send(:devise_user_signed_in?)).to be false
      end
    end

    context 'when Devise is available and user is authenticated' do
      before do
        stub_const('Devise', double)
        warden = double('warden')
        env['warden'] = warden
        allow(warden).to receive(:authenticated?).and_return(true)
      end

      it 'returns true' do
        expect(controller.send(:devise_user_signed_in?)).to be true
      end
    end

    context 'when Devise is available but user is not authenticated' do
      before do
        stub_const('Devise', double)
        warden = double('warden')
        env['warden'] = warden
        allow(warden).to receive(:authenticated?).and_return(false)
      end

      it 'returns false' do
        expect(controller.send(:devise_user_signed_in?)).to be false
      end
    end
  end

  describe '#validate_llama_bot_token' do
    context 'with no authorization header' do
      it 'returns detailed missing_auth_header error' do
        allow(request).to receive(:headers).and_return({})

        result = controller.send(:validate_llama_bot_token)

        expect(result[:valid]).to be false
        expect(result[:error_code]).to eq("LLAMA_AUTH_001")
        expect(result[:error_details][:reason]).to eq("Authorization header is missing")
        expect(result[:error_details][:expected_format]).to eq("Authorization: LlamaBot <signed-token>")
      end
    end

    context 'with incorrect auth scheme' do
      before do
        headers['Authorization'] = 'Bearer some-token'
      end

      it 'returns detailed invalid_auth_scheme error' do
        result = controller.send(:validate_llama_bot_token)

        expect(result[:valid]).to be false
        expect(result[:error_code]).to eq("LLAMA_AUTH_002")
        expect(result[:error_details][:reason]).to eq("Invalid authorization scheme")
        expect(result[:error_details][:received_scheme]).to eq("Bearer")
        expect(result[:error_details][:expected_scheme]).to eq("LlamaBot")
        expect(result[:error_details][:hint]).to include("Ensure the Authorization header uses 'LlamaBot' scheme")
      end
    end

    context 'with missing token after scheme' do
      before do
        headers['Authorization'] = 'LlamaBot'
      end

      it 'returns detailed missing_token error' do
        result = controller.send(:validate_llama_bot_token)

        expect(result[:valid]).to be false
        expect(result[:error_code]).to eq("LLAMA_AUTH_003")
        expect(result[:error_details][:reason]).to eq("Token is missing after scheme")
      end
    end

    context 'with invalid token signature' do
      before do
        headers['Authorization'] = 'LlamaBot invalid-token'
        allow(Rails.application.message_verifier(:llamabot_ws))
          .to receive(:verify)
          .and_raise(ActiveSupport::MessageVerifier::InvalidSignature)
      end

      it 'returns detailed invalid_signature error with debugging info' do
        result = controller.send(:validate_llama_bot_token)

        expect(result[:valid]).to be false
        expect(result[:error_code]).to eq("LLAMA_AUTH_004")
        expect(result[:error_details][:reason]).to eq("Token signature verification failed")
        expect(result[:error_details][:token_prefix]).to eq("invalid-token".slice(0, 20))
        expect(result[:error_details][:verifier_purpose]).to eq(:llamabot_ws)
        expect(result[:error_details][:possible_causes]).to be_an(Array)
        expect(result[:error_details][:possible_causes]).to include("secret_key_base mismatch between token generator and verifier")
      end
    end

    context 'with valid token' do
      let(:valid_token) { 'valid-token' }
      let(:token_data) { { session_id: 'test', user_id: 123 } }

      before do
        headers['Authorization'] = "LlamaBot #{valid_token}"
        allow(Rails.application.message_verifier(:llamabot_ws))
          .to receive(:verify)
          .with(valid_token)
          .and_return(token_data)
      end

      it 'returns valid result with token data' do
        result = controller.send(:validate_llama_bot_token)

        expect(result[:valid]).to be true
        expect(result[:token_data]).to eq(token_data)
        expect(result[:error_code]).to be_nil
      end
    end
  end

  describe '#build_auth_error_payload' do
    let(:error_code) { "LLAMA_AUTH_001" }
    let(:message) { "Test error message" }
    let(:details) { { reason: "test reason", hint: "test hint" } }

    it 'builds a structured error payload with all required fields' do
      result = controller.send(:build_auth_error_payload, error_code, message, details)

      expect(result[:error]).to eq("Unauthorized")
      expect(result[:error_code]).to eq(error_code)
      expect(result[:message]).to eq(message)
      expect(result[:hint]).to eq("test hint")
      expect(result[:details][:reason]).to eq("test reason")
      expect(result[:details][:hint]).to be_nil # hint should be separated
      expect(result[:request_info]).to include(
        controller: controller.class.name,
        action: 'allowed_action',
        method: 'GET',
        path: '/test',
        remote_ip: '127.0.0.1',
        request_id: 'test-request-id'
      )
      expect(result[:timestamp]).to be_present
      expect(result[:documentation_url]).to be_present
    end
  end

  describe '#log_auth_failure' do
    let(:error_payload) do
      {
        error_code: "LLAMA_AUTH_001",
        message: "Test error",
        request_info: {
          controller: "TestController",
          action: "test_action",
          path: "/test",
          remote_ip: "127.0.0.1",
          request_id: "req-123"
        },
        details: { reason: "test reason" },
        hint: "test hint"
      }
    end

    it 'logs error with structured format' do
      expect(Rails.logger).to receive(:error).with(
        /\[LlamaBot Auth Failure\].*code=LLAMA_AUTH_001.*message="Test error".*controller=TestController.*action=test_action/
      )
      expect(Rails.logger).to receive(:debug).with(/\[LlamaBot Auth Failure Details\].*test reason/)
      expect(Rails.logger).to receive(:info).with("[LlamaBot Auth Hint] test hint")

      controller.send(:log_auth_failure, error_payload)
    end

    context 'when no hint is provided' do
      before do
        error_payload.delete(:hint)
      end

      it 'does not log hint' do
        expect(Rails.logger).to receive(:error)
        expect(Rails.logger).to receive(:debug)
        expect(Rails.logger).not_to receive(:info)

        controller.send(:log_auth_failure, error_payload)
      end
    end
  end

  describe 'AUTH_ERRORS constant' do
    it 'defines all expected error codes' do
      expect(LlamaBotRails::AgentAuth::AUTH_ERRORS).to include(
        missing_auth_header: "LLAMA_AUTH_001",
        invalid_auth_scheme: "LLAMA_AUTH_002",
        missing_token: "LLAMA_AUTH_003",
        invalid_signature: "LLAMA_AUTH_004",
        expired_token: "LLAMA_AUTH_005",
        user_not_found: "LLAMA_AUTH_006",
        sign_in_failed: "LLAMA_AUTH_007",
        action_not_whitelisted: "LLAMA_AUTH_008",
        warden_auth_failed: "LLAMA_AUTH_009"
      )
    end

    it 'is frozen to prevent modification' do
      expect(LlamaBotRails::AgentAuth::AUTH_ERRORS).to be_frozen
    end
  end
end