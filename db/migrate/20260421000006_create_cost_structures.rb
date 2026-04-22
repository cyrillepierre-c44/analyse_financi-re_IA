class CreateCostStructures < ActiveRecord::Migration[8.1]
  def change
    create_table :cost_structures do |t|
      t.references :financial_report, null: false, foreign_key: true
      t.integer    :cost_category,    null: false  # enum: cost_of_sales, distribution_marketing, administrative, total
      t.decimal    :fixed_costs,      precision: 15, scale: 2  # Charges fixes
      t.decimal    :variable_costs,   precision: 15, scale: 2  # Charges variables

      t.timestamps
    end

    add_index :cost_structures, [ :financial_report_id, :cost_category ], unique: true
  end
end
