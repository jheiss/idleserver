IdleServer::Application.routes.draw do
  resources :clients do
    member do
      post 'ack'
    end
  end
  resources :metrics do
    collection do
      get 'process_report'
    end
  end

  root :to => 'dashboard#index'
  get 'chart/:chart' => 'dashboard#chart'
end
