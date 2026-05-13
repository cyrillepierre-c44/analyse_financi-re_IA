class CompanyContextPreparationsController < ApplicationController
  def create
    @company = Company.find(params[:company_id])

    if @company.context_processing?
      return redirect_to @company, alert: "Enrichissement déjà en cours, veuillez patienter."
    end

    @company.update!(ia_context_status: "pending")
    AnalyticalPreparationJob.perform_later(@company.id)

    redirect_to @company, notice: "Enrichissement du contexte IA lancé en arrière-plan."
  end
end
