require 'rails_helper'

RSpec.describe LlamaBotRails::UserFeedbacksController, type: :controller do
  routes { LlamaBotRails::Engine.routes }

  let(:mock_user) { double('User', id: 123, email: 'user@example.com') }

  before do
    # Authenticate as a regular (non-admin) user. The default permission checker
    # allows :submit_feedback for any authenticated user.
    allow(LlamaBotRails).to receive(:current_user_resolver).and_return(->(_env) { mock_user })
  end

  describe 'POST #create' do
    let(:selected_element_params) do
      {
        selected_element_html: '<button class="cta">Buy now</button>',
        selected_element_selector: 'div#hero > button.cta',
        selected_element_url: '/pricing'
      }
    end

    it 'persists the selected element fields on the feedback' do
      expect {
        post :create, params: {
          user_feedback: {
            title: 'Quick Feedback',
            description: 'This button is misaligned',
            feedback_type: 'bug'
          }.merge(selected_element_params)
        }
      }.to change(LlamaBotRails::UserFeedback, :count).by(1)

      feedback = LlamaBotRails::UserFeedback.last
      expect(feedback.selected_element_html).to eq(selected_element_params[:selected_element_html])
      expect(feedback.selected_element_selector).to eq(selected_element_params[:selected_element_selector])
      expect(feedback.selected_element_url).to eq(selected_element_params[:selected_element_url])
    end

    it 'still creates feedback when no element is selected' do
      expect {
        post :create, params: {
          user_feedback: { title: 'No element', description: 'Just text', feedback_type: 'general' }
        }
      }.to change(LlamaBotRails::UserFeedback, :count).by(1)

      feedback = LlamaBotRails::UserFeedback.last
      expect(feedback.selected_element_html).to be_nil
      expect(feedback.selected_element_selector).to be_nil
      expect(feedback.selected_element_url).to be_nil
    end

    # SupportIncident #139 (leo-manu): the floating feedback bubble submits with
    # fetch(). #create always redirected, so an async widget submit depended on
    # browser redirect handling and surfaced as a network-stage "Failed to fetch"
    # in Chrome. The widget now asks for JSON; the controller must answer in kind.
    context 'when the request asks for JSON (the feedback bubble)' do
      it 'returns 201 with the feedback id and url instead of redirecting' do
        expect {
          post :create, params: {
            user_feedback: { title: 'Bubble', description: 'From the widget', feedback_type: 'bug' }
          }, format: :json
        }.to change(LlamaBotRails::UserFeedback, :count).by(1)

        expect(response).to have_http_status(:created)
        expect(response.media_type).to eq('application/json')

        body = JSON.parse(response.body)
        feedback = LlamaBotRails::UserFeedback.last
        expect(body['success']).to be(true)
        expect(body['id']).to eq(feedback.id)
        expect(body['url']).to include(feedback.id.to_s)
      end

      it 'returns 422 with the validation errors when the feedback is invalid' do
        expect {
          post :create, params: {
            user_feedback: { title: 'Bad type', description: 'x', feedback_type: 'not_a_real_type' }
          }, format: :json
        }.not_to change(LlamaBotRails::UserFeedback, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.media_type).to eq('application/json')

        body = JSON.parse(response.body)
        expect(body['success']).to be(false)
        expect(body['errors']).to be_an(Array)
        expect(body['errors']).not_to be_empty
      end
    end

    context 'when the request asks for HTML (the normal form)' do
      it 'still redirects to the feedback on success' do
        post :create, params: {
          user_feedback: { title: 'Form', description: 'From the form', feedback_type: 'bug' }
        }

        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(
          LlamaBotRails::Engine.routes.url_helpers.user_feedback_path(LlamaBotRails::UserFeedback.last)
        )
      end

      it 'still re-renders with 422 on validation failure' do
        post :create, params: {
          user_feedback: { title: 'Bad type', description: 'x', feedback_type: 'not_a_real_type' }
        }

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
