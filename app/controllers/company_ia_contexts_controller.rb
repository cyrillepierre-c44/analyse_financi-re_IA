class CompanyIaContextsController < ApplicationController
  def update
    @company = Company.find(params[:company_id])
    @company.update!(ia_context: params.dig(:company, :ia_context))
    redirect_to @company, notice: "Contexte IA enregistré."
  end
end
