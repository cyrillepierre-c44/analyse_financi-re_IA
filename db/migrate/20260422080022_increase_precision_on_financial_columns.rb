class IncreasePrecisionOnFinancialColumns < ActiveRecord::Migration[8.1]
  TABLES = %i[balance_sheets cash_flow_statements income_statements cost_structures].freeze

  def up
    TABLES.each do |table|
      columns_for(table).each do |col|
        change_column table, col, :decimal, precision: 20, scale: 2
      end
    end
  end

  def down
    TABLES.each do |table|
      columns_for(table).each do |col|
        change_column table, col, :decimal, precision: 15, scale: 2
      end
    end
  end

  private

  def columns_for(table)
    ApplicationRecord.connection
                     .columns(table)
                     .select { |c| c.type == :decimal }
                     .map(&:name)
                     .map(&:to_sym)
  end
end
