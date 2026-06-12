Rails.application.routes.draw do
  # Authentication (generator) + signup
  resource :session
  resource :registration, only: %i[ new create ]
  resources :passwords, param: :token

  # Dashboard is the landing page for signed-in users.
  root "dashboard#show"

  # Predictions grid: one page listing fixtures with inline prediction forms.
  # Saving a prediction is a singular resource nested under its fixture:
  #   POST  /fixtures/:fixture_id/prediction  -> predictions#create  (fixture_prediction_path(fixture))
  #   PATCH /fixtures/:fixture_id/prediction  -> predictions#update  (fixture_prediction_path(fixture))
  get "predictions", to: "fixtures#index", as: :predictions
  resources :fixtures, only: [] do
    resource :prediction, only: %i[ create update ]
  end

  # Leaderboard (live-updating via Turbo Streams broadcast to "leaderboard").
  resource :leaderboard, only: :show

  # One champion pick per user; can be created/changed until the tournament starts.
  resource :champion_pick, only: %i[ create update ]

  # Admin: enter/correct results, which triggers rescoring.
  namespace :admin do
    resources :fixtures, only: %i[ index edit update ]
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/*
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
