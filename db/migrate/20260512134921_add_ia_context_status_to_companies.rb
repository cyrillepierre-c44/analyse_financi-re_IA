class AddIaContextStatusToCompanies < ActiveRecord::Migration[8.1]
  def change
    add_column :companies, :ia_context_status, :string, default: "pending"
    add_column :companies, :ia_context_gaps,   :text
  end
end
