class Company < ApplicationRecord
  has_many :financial_reports, dependent: :destroy

  enum :accounting_standard, { pcg: 0, ifrs: 1 }

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  # country et currency ont des valeurs par défaut en DB (France / EUR)

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
