Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Defines the root path route ("/")
  root to: 'top#index'

  get 'login', to: 'sessions#new'

  # Demo/sample routes: enable only in development and test environments
  if Rails.env.development? || Rails.env.test?
    resources :eml_inputs, only: [:new, :create]
  end

  namespace :api do
    namespace :v1 do
      resources :mail_queues, only: [:index, :create, :show, :update, :destroy]
    end
  end

  # https://github.com/rails/mission_control-jobs
  namespace :admin do
    mount MissionControl::Jobs::Engine, at: "/jobs"
  end
end
