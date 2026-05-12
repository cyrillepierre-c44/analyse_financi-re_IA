class CreateQuestions < ActiveRecord::Migration[8.1]
  def change
    create_table :questions do |t|
      t.integer  :position,    null: false
      t.text     :text,        null: false
      t.string   :answer_type, null: false, default: "single"
      t.json     :options,     null: false, default: []

      t.timestamps
    end
    add_index :questions, :position
  end
end
