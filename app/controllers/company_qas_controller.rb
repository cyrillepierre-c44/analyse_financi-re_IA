class CompanyQasController < ApplicationController
  def create
    @company = Company.find(params[:company_id])
    @answers = QaGeneratorService.call(@company)
  rescue => e
    @error = e.message
  end
end
