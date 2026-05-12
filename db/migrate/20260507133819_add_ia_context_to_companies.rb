class AddIaContextToCompanies < ActiveRecord::Migration[8.1]
  def change
    add_column :companies, :ia_context, :text
  end
end
