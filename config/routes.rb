Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Defines the root path route ("/")
  root to: 'top#index'

  get 'login', to: 'sessions#new'

  namespace :api do
    namespace :v1 do
      resources :mail_queues, only: [:index, :create, :show, :update, :destroy]
    end
  end
end
