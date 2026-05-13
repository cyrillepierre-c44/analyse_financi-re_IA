class CompanyDocumentsController < ApplicationController
  before_action :set_company

  def create
    files = Array(params[:files])
    return redirect_to @company, alert: "Aucun fichier sélectionné." if files.empty?

    uploaded = 0
    errors   = []

    files.each do |upload|
      next unless upload.respond_to?(:content_type)
      unless CompanyDocument::ACCEPTED_FORMATS.include?(upload.content_type)
        errors << "Format non supporté : #{upload.original_filename}"
        next
      end

      doc = @company.company_documents.new(
        document_type:     params[:document_type].presence || "annual_report",
        status:            "pending",
        original_filename: upload.original_filename
      )
      doc.file.attach(upload)

      if doc.save
        uploaded += 1
      else
        errors << "Erreur sur #{upload.original_filename} : #{doc.errors.full_messages.join(', ')}"
      end
    end

    notice = "#{uploaded} document(s) ajouté(s)."
    alert  = errors.join(" | ") if errors.any?

    redirect_to @company, notice: notice, alert: alert
  end

  def destroy
    doc = @company.company_documents.find(params[:id])
    doc.file.purge
    doc.destroy
    redirect_to @company, notice: "Document supprimé."
  end

  private

  def set_company
    @company = Company.find(params[:company_id])
  end
end
