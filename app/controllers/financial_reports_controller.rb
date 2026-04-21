class FinancialReportsController < ApplicationController
  def show
    @company = Company.find(params[:company_id])
    @report  = @company.financial_reports
                       .includes(:income_statement, :balance_sheet, :cash_flow_statement, :cost_structures)
                       .find(params[:id])

    # Exercice N-1 pour comparaisons
    @prev_report = @company.financial_reports
                           .includes(:income_statement, :balance_sheet)
                           .find_by(fiscal_year: @report.fiscal_year - 1)
  end
end
