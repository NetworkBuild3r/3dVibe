Rails.application.routes.draw do
  get "/up", to: "health#show"

  namespace :api do
    namespace :v1 do
      resource :session, only: %i[create destroy]
      get :me, to: "sessions#show"

      resources :libraries, only: %i[index show create] do
        post :scan, on: :member
      end

      resources :models, controller: "vibe_models", only: %i[index show] do
        resources :archive_members, only: :index
      end

      resources :assets, only: :show do
        get :content, on: :member
      end

      resources :archive_members, only: [] do
        get :preview, on: :member
      end

      get :search, to: "search#index"

      resources :curation_proposals, only: %i[index create] do
        post :approve, on: :member
        post :reject, on: :member
        post :fetch, on: :collection
        post :ingest, on: :collection
        post :bulk, on: :collection
      end

      resources :printers, only: %i[index show create update destroy]
      resources :print_jobs, only: %i[index show create] do
        post :cancel, on: :member
      end
      resources :invites, only: %i[index create] do
        post :revoke, on: :member
      end
      get "invites/token/:token", to: "invites#preview"
      post "invites/:token/redeem", to: "invites#redeem"

      resources :uploads, only: %i[create show update] do
        post :complete, on: :member
        post :direct, on: :collection
      end
    end
  end
end
