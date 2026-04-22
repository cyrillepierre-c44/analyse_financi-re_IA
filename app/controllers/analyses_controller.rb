class AnalysesController < ApplicationController
  def create
    @company = Company.find(params[:company_id])

    # Régénérer seulement si forcé ou si aucune analyse n'existe
    if @company.ai_analysis.present? && params[:force] != "1"
      @analysis = @company.ai_analysis
    else
      @analysis = FinancialAnalysisGenerator.call(@company)
      @company.update!(ai_analysis: @analysis, ai_analyzed_at: Time.current)
    end
  rescue => e
    @error = e.message
  end
end
