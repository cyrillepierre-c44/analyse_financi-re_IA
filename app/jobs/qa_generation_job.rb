class QaGenerationJob < ApplicationJob
  queue_as :default

  def perform(company_id)
    company = Company.find(company_id)
    company.update!(qa_status: "processing")
    QaGeneratorService.call(company)
    company.update!(qa_status: "ready")
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "[QaGenerationJob] Company #{company_id} introuvable"
  rescue => e
    Company.find_by(id: company_id)&.update!(qa_status: "error")
    Rails.logger.error "[QaGenerationJob] #{e.class}: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
    raise
  end
end
