class AnalyticalPreparationJob < ApplicationJob
  queue_as :default

  def perform(company_id)
    company = Company.find(company_id)
    AnalyticalPreparationAgent.call(company)
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "[AnalyticalPreparationJob] Company #{company_id} introuvable"
  end
end
