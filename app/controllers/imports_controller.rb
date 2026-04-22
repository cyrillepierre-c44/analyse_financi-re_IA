class ImportsController < ApplicationController
  def new
    @company = Company.find(params[:company_id])
  end

  def create
    @company    = Company.find(params[:company_id])
    fiscal_year = params[:fiscal_year].present? ? params[:fiscal_year].to_i : Date.today.year - 1
    upload      = params[:pdf_file]

    unless upload.present?
      flash.now[:alert] = "Merci de sélectionner un fichier PDF."
      render :new, status: :unprocessable_entity and return
    end

    tmp_path = Rails.root.join("tmp", "import_#{SecureRandom.hex(8)}_#{upload.original_filename}")
    File.binwrite(tmp_path, upload.read)

    reports = FinancialPdfImporter.call(
      pdf_path:    tmp_path.to_s,
      company:     @company,
      fiscal_year: fiscal_year
    )

    years_label = reports.map(&:fiscal_year).sort.join(", ")
    redirect_to company_path(@company),
                notice: "Import réussi — #{reports.size} exercice(s) chargé(s) : #{years_label}."
  rescue => e
    @error = e.message
    flash.now[:alert] = "Erreur lors de l'import : #{@error}"
    render :new, status: :unprocessable_entity
  ensure
    File.delete(tmp_path) if defined?(tmp_path) && tmp_path && File.exist?(tmp_path.to_s)
  end
end
