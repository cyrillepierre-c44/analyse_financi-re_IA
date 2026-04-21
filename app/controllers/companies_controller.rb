class CompaniesController < ApplicationController
  def index
    @companies = Company.includes(:financial_reports).order(:name)
  end

  def show
    @company = Company.find(params[:id])
    @reports = @company.financial_reports
                       .includes(:income_statement, :balance_sheet)
                       .order(fiscal_year: :asc)
  end

  def new
    @company = Company.new(country: "France", currency: "EUR", accounting_standard: :pcg)
  end

  def create
    @company = Company.new(company_params)
    if @company.save
      redirect_to @company, notice: "Société « #{@company.name} » créée avec succès."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def company_params
    params.require(:company).permit(
      :name, :siren, :sector, :country, :currency, :accounting_standard, :is_consolidated
    )
  end
end
