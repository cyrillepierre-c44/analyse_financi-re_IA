class CompaniesController < ApplicationController
  def index
    @companies = Company.includes(:financial_reports).order(:name)
  end

  def show
    @company = Company.find(params[:id])
    @reports = @company.financial_reports
                       .includes(:income_statement, :balance_sheet)
                       .order(fiscal_year: :desc)
  end
end
