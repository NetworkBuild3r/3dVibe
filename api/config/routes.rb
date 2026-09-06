Rails.application.routes.draw do
  get "/up", to: "health#show"
  get "/covers/:filename", to: "api/v1/covers#show", constraints: { filename: /[0-9]+\.webp/ }

  namespace :api do
    namespace :v1 do
      resource :session, only: %i[create destroy]
      get :me, to: "sessions#show"

      resources :libraries, only: %i[index show create] do
        get :scan, on: :member, action: :show_scan
        post :scan, on: :member
        get :ops, on: :member
        post "duplicates/analyze", on: :member, to: "duplicates#analyze"
      end

      get :ops, to: "ops#show"

      resources :creators, only: %i[index show]
      post "covers/writeback", to: "covers#writeback"
      post "geometry/writeback", to: "geometry#writeback"

      resources :models, controller: "vibe_models", only: %i[index show] do
        resources :archive_members, only: :index
        post :like, on: :member
        delete :like, on: :member, action: :unlike
        post :split, on: :member
        post :merge, on: :collection
      end

      resources :likes, only: :index
      resources :bookmark_folders, only: %i[index show create update destroy] do
        resources :bookmarks, only: %i[create destroy]
      end
      resources :duplicates, only: :index do
        post :keep, on: :member
        post :dismiss, on: :member
        post :merge, on: :member
      end

      resources :assets, only: :show do
        get :content, on: :member
      end

      resources :archive_members, only: :show do
        get :preview, on: :member
        get :content, on: :member
      end

      get :search, to: "search#index"

      resource :curator_settings, only: %i[show update] do
        put :xai_api_key, action: :update_xai_api_key
        delete :xai_api_key, action: :destroy_xai_api_key
      end

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
        post :retry, on: :member
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
