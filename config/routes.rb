Rails.application.routes.draw do
  root "companies#index"

  resources :companies do
    resources :financial_reports, only: [ :show ]
    resources :imports,           only: [ :new, :create ]
    resource  :analysis,          only: [ :create ]
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
