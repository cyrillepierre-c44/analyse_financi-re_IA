class FinancialReport < ApplicationRecord
  belongs_to :company
  has_one :income_statement,    dependent: :destroy
  has_one :balance_sheet,       dependent: :destroy
  has_one :cash_flow_statement, dependent: :destroy
  has_many :cost_structures,    dependent: :destroy

  enum :period_type,         { annual: 0, semi_annual: 1, quarterly: 2 }
  enum :accounting_standard, { pcg: 0, ifrs: 1 }
  enum :income_format,       { nature: 0, fonction: 1 }

  validates :fiscal_year, presence: true
  validates :period_end_date, presence: true
  validates :fiscal_year, uniqueness: { scope: :company_id }

  # ── RENTABILITÉ ÉCONOMIQUE ────────────────────────────────────────────
  # Re = EBIT * (1 - IS) / Actif économique
  def economic_return(tax_rate: 0.25)
    ae = balance_sheet&.economic_assets
    ebit = income_statement&.ebit
    return nil unless ae&.positive? && ebit
    ebit * (1 - tax_rate) / ae
  end

  # Décomposition Re = Marge EBIT * Rotation économique
  def ebit_margin_after_tax(tax_rate: 0.25)
    revenue = income_statement&.revenue
    ebit = income_statement&.ebit
    return nil unless revenue&.positive? && ebit
    ebit * (1 - tax_rate) / revenue
  end

  def economic_rotation
    ae = balance_sheet&.economic_assets
    revenue = income_statement&.revenue
    return nil unless ae&.positive? && revenue
    revenue / ae
  end

  # ── RENTABILITÉ DES CAPITAUX PROPRES (ROE) ────────────────────────────
  # Rcp = Résultat net hors exceptionnel / Capitaux propres
  def return_on_equity
    cp = balance_sheet&.total_equity
    rn = income_statement&.net_income
    return nil unless cp&.positive? && rn
    rn / cp
  end

  # ── EFFET DE LEVIER ───────────────────────────────────────────────────
  # Rcp = Re + (Re - coût dette après IS) * (Dettes / CP)
  def leverage_effect(tax_rate: 0.25, debt_cost_before_tax: nil)
    re = economic_return(tax_rate: tax_rate)
    nd = balance_sheet&.net_financial_debt
    cp = balance_sheet&.total_equity
    return nil unless re && nd && cp&.positive?

    cost_after_tax = if debt_cost_before_tax
                       debt_cost_before_tax * (1 - tax_rate)
                     elsif income_statement&.financial_expenses && nd.positive?
                       (income_statement.financial_expenses / nd) * (1 - tax_rate)
                     else
                       return nil
                     end

    re + (re - cost_after_tax) * (nd / cp)
  end

  # ── RATIO D'ENDETTEMENT ───────────────────────────────────────────────
  # Dettes financières nettes / EBE
  def debt_ratio
    nd = balance_sheet&.net_financial_debt
    ebitda = income_statement&.ebitda_calculated
    return nil unless nd && ebitda&.positive?
    nd / ebitda
  end

  # ── RATIOS BFR EN JOURS ───────────────────────────────────────────────

  # Ratio BFR global = BFR / CA TTC * 365
  def wcr_in_days(vat_rate: 0.20)
    bfr = balance_sheet&.working_capital_requirement
    revenue = income_statement&.revenue
    return nil unless bfr && revenue&.positive?
    bfr / (revenue * (1 + vat_rate)) * 365
  end

  # Rotation crédit clients = (Clients) / CA TTC * 365
  def days_sales_outstanding(vat_rate: 0.20)
    clients = balance_sheet&.trade_receivables
    revenue = income_statement&.revenue
    return nil unless clients && revenue&.positive?
    clients / (revenue * (1 + vat_rate)) * 365
  end

  # Rotation crédit fournisseurs = Dettes fournisseurs / Achats TTC * 365
  def days_payable_outstanding(vat_rate: 0.20)
    fournisseurs = balance_sheet&.trade_payables
    achats = income_statement&.raw_materials_purchases
    return nil unless fournisseurs && achats&.positive?
    fournisseurs / (achats * (1 + vat_rate)) * 365
  end

  # Ratio politique industrielle = Investissements / Dotations amortissements
  def industrial_policy_ratio
    capex = cash_flow_statement&.capital_expenditure
    amort = cash_flow_statement&.depreciation_amortization || income_statement&.depreciation_amortization
    return nil unless capex && amort&.positive?
    capex / amort
  end

  # ── POINT MORT ────────────────────────────────────────────────────────

  def total_fixed_costs
    cost_structures.sum(:fixed_costs)
  end

  def total_variable_costs
    cost_structures.sum(:variable_costs)
  end

  # Marge sur coûts variables = CA - Charges variables
  def variable_margin
    revenue = income_statement&.revenue
    return nil unless revenue
    revenue - total_variable_costs
  end

  # Taux de marge sur coûts variables = MCV / CA
  def variable_margin_rate
    revenue = income_statement&.revenue
    return nil unless revenue&.positive?
    variable_margin / revenue
  end

  # Point mort en € = Charges fixes / Taux MCV
  def break_even_point
    rate = variable_margin_rate
    return nil unless rate&.positive?
    total_fixed_costs / rate
  end

  # Position par rapport au point mort = CA / Point mort - 1
  def break_even_distance
    bep = break_even_point
    revenue = income_statement&.revenue
    return nil unless bep&.positive? && revenue
    revenue / bep - 1
  end

  # Levier opérationnel = MCV / (MCV - Charges fixes)
  def operating_leverage
    vm = variable_margin
    return nil unless vm
    denominator = vm - total_fixed_costs
    return nil unless denominator.positive?
    vm / denominator
  end

  # ── TAUX DE CROISSANCE ANNUEL MOYEN (TCAM) ───────────────────────────
  # Calculé au niveau Company sur plusieurs exercices
end
