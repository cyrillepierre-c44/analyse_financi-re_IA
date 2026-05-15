class AddCompanyToQuestions < ActiveRecord::Migration[8.1]
  def up
    add_reference :questions, :company, null: true, foreign_key: true

    # Associe les questions existantes à Laurent Perrier
    lp = Company.where("LOWER(name) LIKE ? OR LOWER(name) LIKE ?",
                       "%laurent%perrier%", "%laurent-perrier%").first
    if lp
      count = Question.update_all(company_id: lp.id)
      say "#{count} questions associées à #{lp.name} (id #{lp.id})"
    else
      say "AVERTISSEMENT : Laurent Perrier introuvable — questions laissées sans company_id"
    end

    # Index composé pour la contrainte d'unicité (position par société)
    add_index :questions, [:company_id, :position], unique: true,
              name: "index_questions_on_company_id_and_position"
    remove_index :questions, :position,
                 name: "index_questions_on_position", if_exists: true
  end

  def down
    add_index :questions, :position, name: "index_questions_on_position"
    remove_index :questions, [:company_id, :position],
                 name: "index_questions_on_company_id_and_position", if_exists: true
    remove_reference :questions, :company
  end
end
