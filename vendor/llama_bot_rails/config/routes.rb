LlamaBotRails::Engine.routes.draw do
  get "unauthorized", to: "application#unauthorized"

  # Entry point for the chat UI's single "Inbox" tab. The five Inbox pages have
  # different access levels — Tickets is engineers-only — so the tab cannot
  # point at a fixed page without dead-ending whoever may not see it. This
  # redirects to the first page the visitor is actually allowed to open.
  get "inbox", to: "inbox#show", as: :inbox

  # The engine's own sign-in page. Engine surfaces run inside an iframe in the
  # chat UI, so they need a sign-in screen that returns the visitor to the page
  # they asked for, and whose wording the engine controls even when the host app
  # restyles /users/sign_in. See SessionsController.
  get "sign_in", to: "sessions#new", as: :sign_in
  post "sign_in", to: "sessions#create"

  # Public shareable links (no authentication required)
  resources :shared_links, only: [:show], param: :token, path: 'shared' do
    member do
      get :download
      get :stream
    end
  end
  # post "agent/command", to: "agent#command"
  # get "agent/chat", to: "agent#chat"
  # get "/", to: "agent#chat"
  # get "/ws", to: "agent#chat_ws"
  # get "agent/chat_ws", to: "agent#chat_ws"
  # Mints the per-user agent token for the cross-origin chat UI. Devise session only —
  # see AgentTokenController for why that distinction is load-bearing.
  get "agent/token", to: "agent_token#show"
  match "agent/token", to: "agent_token#options", via: :options

  # Recent Rails crashes, polled by LlamaBot mid-turn so Leo can fix what it
  # just broke before handing back. Agent-token gated — see ErrorsController.
  get "errors", to: "errors#index", as: :errors

  get "agent/threads", to: "agent#threads"
  get "agent/chat-history/:thread_id", to: "agent#chat_history"
  post "agent/send_message", to: "agent#send_message"
  # get "agent/test_streaming", to: "agent#test_streaming"

  resources :projects

  # Activity / audit / adoption (docs/activity_events.md). Read-only, gated on
  # can?(:view_activity). Static segments are declared before :id so "usage"
  # and "history" are never parsed as an event id.
  get "activity", to: "activity_events#index", as: :activity
  get "activity/usage", to: "activity_events#usage", as: :activity_usage
  get "activity/history/:subject_type/:subject_id",
      to: "activity_events#history",
      as: :activity_history,
      constraints: { subject_type: /[A-Za-z0-9:]+/, subject_id: /[^\/]+/ }
  get "activity/:id", to: "activity_events#show", as: :activity_event

  # Release / version-notes. index/show are readable by any signed-in user;
  # authoring actions + notify are admin-gated in the controller.
  resources :releases do
    member do
      post :notify
    end
  end

  resources :tickets do
    collection do
      get :timeline
    end
    member do
      patch :move
      delete :remove_image
      post :share_attachment
    end
    resources :comments, only: [:create, :destroy], controller: 'ticket_comments'
  end

  # User Feedback routes
  resources :user_feedbacks, path: 'feedback' do
    collection do
      get :dashboard
      get :kanban
    end
    member do
      post :add_tag
      delete :remove_tag
      delete :remove_attachment
      post :share_attachment
      patch :move
    end
    resources :comments, only: [:create, :update, :destroy], controller: 'feedback_comments' do
      member do
        delete :remove_attachment
      end
    end
  end

  # User Request routes
  resources :user_requests, path: 'requests' do
    collection do
      get :dashboard
    end
    member do
      post :add_tag
      delete :remove_tag
      post :respond_to_request
      delete :remove_attachment
      post :share_attachment
    end
    resources :comments, only: [:create, :update, :destroy], controller: 'feedback_comments' do
      member do
        delete :remove_attachment
      end
    end
  end

  # Tags management
  resources :tags, only: [:index, :new, :create, :edit, :update, :destroy]

  # Conversations (Direct Messaging)
  resources :conversations, only: [:index, :show, :create] do
    member do
      get :messages
    end
    resources :messages, only: [:create], controller: 'direct_messages'
  end

  # Users (for @mentions)
  get 'users/search', to: 'users#search'

  # Notifications
  resources :notifications, only: [:index] do
    collection do
      get :unread_count
      post :mark_read
    end
    member do
      post :read
    end
  end
end