class AddResearchDevelopmentCostsToIncomeStatements < ActiveRecord::Migration[8.1]
  def change
    add_column :income_statements, :research_development_costs, :decimal, precision: 20, scale: 2
  end
end
