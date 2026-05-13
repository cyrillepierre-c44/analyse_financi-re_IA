class CreateCompanyDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :company_documents do |t|
      t.references :company, null: false, foreign_key: true
      t.string  :document_type, null: false, default: "supplementary"
      t.string  :status,        null: false, default: "pending"
      t.text    :extracted_text
      t.text    :processing_notes
      t.string  :original_filename
      t.timestamps
    end

    add_index :company_documents, [ :company_id, :status ]
  end
end
