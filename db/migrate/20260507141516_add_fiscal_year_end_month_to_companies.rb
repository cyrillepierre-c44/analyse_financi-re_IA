class AddFiscalYearEndMonthToCompanies < ActiveRecord::Migration[8.1]
  def change
    add_column :companies, :fiscal_year_end_month, :integer, default: 12, null: false
  end
end
