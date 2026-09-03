require 'rails_helper'

# The activity tracker is included into ActionController::Base at engine init, so
# its before_action can run AHEAD of a host app's verify_authenticity_token.
#
# If resolving the actor calls Devise's `current_user`, Warden runs its strategies
# right there. On POST /users/sign_in that authenticates from the form params, and
# Devise's clean_up_csrf_token_on_authentication deletes session[:_csrf_token]
# before it is ever verified -- the CORRECT password is then rejected and the user
# can never sign in. Wrong passwords behave normally, which is why this went
# undetected across four boxes (mothership SupportIncident #187; diagnosed on
# leo-mezuli 2026-08-21).
#
# The invariant: resolving the actor must never trigger Warden strategy execution.
RSpec.describe LlamaBotRails::ActivityTracking, "#llama_activity_actor" do
  let(:controller) { ActionController::Base.new }
  let(:warden) { double('Warden::Proxy') }
  let(:env) { { 'warden' => warden } }

  before do
    allow(controller).to receive(:request)
      .and_return(double('ActionDispatch::Request', env: env))
    # The dummy app has no Devise, so teach the controller which helpers exist.
    allow(controller).to receive(:respond_to?).and_call_original
  end

  def actor_method_is(name)
    LlamaBotRails.config.activity_actor_method = name
    allow(controller).to receive(:respond_to?).with(name, true).and_return(true)
  end

  context 'when the actor method is a Devise current_<scope> helper' do
    it 'reads the already-authenticated user from warden instead of calling current_user' do
      actor_method_is(:current_user)
      user = double('User')
      expect(warden).to receive(:user).with(:user).and_return(user)
      expect(controller).not_to receive(:current_user)

      expect(controller.send(:llama_activity_actor)).to eq(user)
    end

    it 'returns nil for an unauthenticated request without running a strategy' do
      actor_method_is(:current_user)
      expect(warden).to receive(:user).with(:user).and_return(nil)

      expect(controller.send(:llama_activity_actor)).to be_nil
    end

    it 'maps the helper name onto the matching warden scope' do
      actor_method_is(:current_admin)
      expect(warden).to receive(:user).with(:admin).and_return(nil)

      controller.send(:llama_activity_actor)
    end
  end

  context 'when the host configures its own actor method' do
    it "calls it as given -- a custom method is the host app's business" do
      actor_method_is(:whodunnit)
      actor = double('Actor')
      allow(controller).to receive(:whodunnit).and_return(actor)
      expect(warden).not_to receive(:user)

      expect(controller.send(:llama_activity_actor)).to eq(actor)
    end
  end

  context 'when there is no warden in the request env' do
    let(:env) { {} }

    it 'falls back to the configured method rather than blowing up' do
      actor_method_is(:current_user)
      allow(controller).to receive(:current_user).and_return(nil)

      expect { controller.send(:llama_activity_actor) }.not_to raise_error
    end
  end

  context 'when the actor method is not defined on the controller at all' do
    it 'returns nil' do
      LlamaBotRails.config.activity_actor_method = :current_user

      expect(controller.send(:llama_activity_actor)).to be_nil
    end
  end
end
