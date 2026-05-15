class AddQaStatusToCompanies < ActiveRecord::Migration[8.1]
  def change
    add_column :companies, :qa_status, :string, null: false, default: "pending"
  end
end
