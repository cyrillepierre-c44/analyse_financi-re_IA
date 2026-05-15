class AnalyticalPreparationJob < ApplicationJob
  queue_as :default

  def perform(company_id)
    company = Company.find(company_id)
    AnalyticalPreparationAgent.call(company)
    QuestionExtractionService.call(company) if company.questions.none?
    QaGenerationJob.perform_later(company_id)
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "[AnalyticalPreparationJob] Company #{company_id} introuvable"
  end
end
