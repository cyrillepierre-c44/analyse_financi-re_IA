class CreateFinancialReports < ActiveRecord::Migration[8.1]
  def change
    create_table :financial_reports do |t|
      t.references :company,             null: false, foreign_key: true
      t.integer    :fiscal_year,         null: false
      t.date       :period_end_date,     null: false
      t.integer    :period_type,         null: false, default: 0  # enum: annual, semi_annual, quarterly
      t.integer    :accounting_standard, null: false, default: 0  # enum: pcg, ifrs
      t.boolean    :is_consolidated,     null: false, default: false
      t.integer    :income_format,       null: false, default: 0  # enum: nature, fonction
      t.string     :source_file
      t.text       :notes

      t.timestamps
    end

    add_index :financial_reports, [ :company_id, :fiscal_year ], unique: true
    add_index :financial_reports, :fiscal_year
  end
end
