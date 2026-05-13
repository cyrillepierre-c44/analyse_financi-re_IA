class Company < ApplicationRecord
  has_many :financial_reports,  dependent: :destroy
  has_many :company_answers,    dependent: :destroy
  has_many :questions,          through: :company_answers
  has_many :company_documents,  dependent: :destroy

  enum :accounting_standard,  { pcg: 0, ifrs: 1 }
  attribute :ia_context_status, :string, default: "pending"
  enum :ia_context_status,    { pending: "pending", processing: "processing",
                                 ready: "ready", error: "error" },
       prefix: :context

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :fiscal_year_end_month, inclusion: { in: 1..12 }
  # country et currency ont des valeurs par défaut en DB (France / EUR)

  # ── LIBELLÉ DE L'EXERCICE FISCAL ─────────────────────────────────────────
  # Si la clôture est ≤ juin, l'exercice chevauche 2 années civiles : "2021-22"
  # Sinon (clôture ≥ juillet) l'exercice est dans une seule année : "2022"
  def fiscal_year_label(year)
    if fiscal_year_end_month <= 6
      "#{year - 1}-#{year.to_s[-2..]}"
    else
      year.to_s
    end
  end

  def fiscal_year_end_label(year)
    month_name = Date::MONTHNAMES[fiscal_year_end_month]
    "#{month_name} #{year}"
  end

  # ── TAUX DE CROISSANCE ANNUEL MOYEN (TCAM) DU CA ─────────────────────────
  # TCAM = (CA_N / CA_0)^(1/n) - 1
  def cagr_revenue
    sorted = financial_reports
               .includes(:income_statement)
               .order(:fiscal_year)
               .select { |r| r.income_statement&.revenue&.positive? }
    return nil if sorted.size < 2

    first_report = sorted.first
    last_report  = sorted.last
    n = last_report.fiscal_year - first_report.fiscal_year
    return nil if n <= 0

    (last_report.income_statement.revenue / first_report.income_statement.revenue) ** (1.0 / n) - 1
  end

  # TCAM du résultat net
  def cagr_net_income
    sorted = financial_reports
               .includes(:income_statement)
               .order(:fiscal_year)
               .select { |r| r.income_statement&.net_income&.positive? }
    return nil if sorted.size < 2

    first_report = sorted.first
    last_report  = sorted.last
    n = last_report.fiscal_year - first_report.fiscal_year
    return nil if n <= 0

    (last_report.income_statement.net_income / first_report.income_statement.net_income) ** (1.0 / n) - 1
  end
end
