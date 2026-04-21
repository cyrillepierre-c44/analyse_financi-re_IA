class ImportsController < ApplicationController
  def new
    @company = Company.find(params[:company_id])
  end

  def create
    @company    = Company.find(params[:company_id])
    fiscal_year = params[:fiscal_year].to_i
    upload      = params[:pdf_file]

    unless upload.present?
      flash.now[:alert] = "Merci de sélectionner un fichier PDF."
      render :new, status: :unprocessable_entity and return
    end

    tmp_path = Rails.root.join("tmp", "import_#{SecureRandom.hex(8)}_#{upload.original_filename}")
    File.binwrite(tmp_path, upload.read)

    report = FinancialPdfImporter.call(
      pdf_path:    tmp_path.to_s,
      company:     @company,
      fiscal_year: fiscal_year
    )

    redirect_to company_financial_report_path(@company, report),
                notice: "Import réussi — exercice #{fiscal_year} chargé."
  rescue => e
    @error = e.message
    flash.now[:alert] = "Erreur lors de l'import : #{@error}"
    render :new, status: :unprocessable_entity
  ensure
    File.delete(tmp_path) if defined?(tmp_path) && tmp_path && File.exist?(tmp_path.to_s)
  end
end
