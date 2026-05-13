Rails.application.routes.draw do
  root "companies#index"

  resources :companies do
    resources :financial_reports, only: [ :show ]
    resources :imports,           only: [ :new, :create ]
    resource  :analysis,          only: [ :create ]
    resource  :qa,                only: [ :create ], controller: "company_qas"
    resource  :ia_context,        only: [ :update ], controller: "company_ia_contexts"
    resources :company_documents, only: [ :create, :destroy ]
    resource  :context_preparation, only: [ :create ], controller: "company_context_preparations"
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
