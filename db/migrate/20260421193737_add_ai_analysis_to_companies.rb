class AddAiAnalysisToCompanies < ActiveRecord::Migration[8.1]
  def change
    add_column :companies, :ai_analysis, :text
    add_column :companies, :ai_analyzed_at, :datetime
  end
end
