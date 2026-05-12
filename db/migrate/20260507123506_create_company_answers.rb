class CreateCompanyAnswers < ActiveRecord::Migration[8.1]
  def change
    create_table :company_answers do |t|
      t.references :company,          null: false, foreign_key: true
      t.references :question,         null: false, foreign_key: true
      t.json       :selected_options, null: false, default: []
      t.datetime   :generated_at

      t.timestamps
    end
    add_index :company_answers, [ :company_id, :question_id ], unique: true
  end
end
