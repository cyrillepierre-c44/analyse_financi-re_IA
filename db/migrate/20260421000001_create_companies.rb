class CreateCompanies < ActiveRecord::Migration[8.1]
  def change
    create_table :companies do |t|
      t.string  :name,                 null: false
      t.string  :siren
      t.string  :sector
      t.string  :country,              default: "France", null: false
      t.integer :accounting_standard,  null: false, default: 0  # enum: pcg, ifrs
      t.boolean :is_consolidated,      null: false, default: false
      t.string  :currency,             default: "EUR", null: false

      t.timestamps
    end

    add_index :companies, :name
    add_index :companies, :siren, unique: true, where: "siren IS NOT NULL"
  end
end
