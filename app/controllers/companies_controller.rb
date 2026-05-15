class CompaniesController < ApplicationController
  def index
    @companies = Company.includes(:financial_reports).order(:name)
  end

  def show
    @company = Company.includes(company_documents: { file_attachment: :blob }).find(params[:id])
    @reports = @company.financial_reports
                       .includes(:income_statement, :balance_sheet, :cash_flow_statement, :cost_structures)
                       .order(fiscal_year: :asc)
  end

  def new
    @company = Company.new(country: "France", currency: "EUR", accounting_standard: :pcg)
  end

  def destroy
    @company = Company.find(params[:id])
    name = @company.name
    @company.destroy!
    redirect_to companies_path, notice: "Société « #{name} » supprimée."
  end

  def create
    # ── Chemin 1 : création depuis un PDF ──────────────────────────────
    if params[:pdf_file].present?
      tmp_path = nil
      begin
        upload   = params[:pdf_file]
        tmp_path = Rails.root.join("tmp", "company_#{SecureRandom.hex(8)}_#{upload.original_filename}")
        File.binwrite(tmp_path, upload.read)

        @company = CompanyPdfImporter.call(pdf_path: tmp_path.to_s)

        AnalyticalPreparationJob.perform_later(@company.id)

        years_label = @company.financial_reports.order(:fiscal_year).pluck(:fiscal_year).join(", ")
        redirect_to @company,
                    notice: "Société « #{@company.name} » créée — exercice(s) : #{years_label}. " \
                            "Enrichissement du contexte et diagnostic Q&A lancés en arrière-plan."
      rescue => e
        @company = Company.new(country: "France", currency: "EUR", accounting_standard: :pcg)
        flash.now[:alert] = "Erreur lors de l'analyse du PDF : #{e.message}"
        render :new, status: :unprocessable_entity
      ensure
        File.delete(tmp_path) if tmp_path && File.exist?(tmp_path.to_s)
      end
      return
    end

    # ── Chemin 2 : formulaire manuel ───────────────────────────────────
    @company = Company.new(company_params)
    if @company.save
      redirect_to @company, notice: "Société « #{@company.name} » créée avec succès."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def company_params
    params.require(:company).permit(
      :name, :siren, :sector, :country, :currency, :accounting_standard, :is_consolidated,
      :ia_context, :fiscal_year_end_month
    )
  end
end
