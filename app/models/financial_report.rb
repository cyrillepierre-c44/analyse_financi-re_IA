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

  # ── RENTABILITÉ ÉCONOMIQUE ────────────────────────────────────────────────
  # Re = EBIT(1 - t) / Actif économique
  def economic_return(tax_rate: 0.25)
    ae   = balance_sheet&.economic_assets
    ebit = income_statement&.ebit
    return nil unless ae&.positive? && ebit
    ebit * (1 - tax_rate) / ae
  end

  # Décomposition Re = Marge EBIT(1-t) × Rotation économique
  def ebit_margin_after_tax(tax_rate: 0.25)
    revenue = income_statement&.revenue
    ebit    = income_statement&.ebit
    return nil unless revenue&.positive? && ebit
    ebit * (1 - tax_rate) / revenue
  end

  def economic_rotation
    ae      = balance_sheet&.economic_assets
    revenue = income_statement&.revenue
    return nil unless ae&.positive? && revenue
    revenue / ae
  end

  # ── RENTABILITÉ DES CAPITAUX PROPRES (Rcp / ROE) ─────────────────────────
  def return_on_equity
    cp = balance_sheet&.total_equity
    rn = income_statement&.net_income
    return nil unless cp&.positive? && rn
    rn / cp
  end

  # Retour sur actif total (ROA)
  def return_on_assets
    rn = income_statement&.net_income
    ta = balance_sheet&.total_assets
    return nil unless rn && ta&.positive?
    rn / ta
  end

  # ── EFFET DE LEVIER ───────────────────────────────────────────────────────
  # Rcp = Re + (Re - i*(1-t)) * (D_nette / CP)
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

  # ── COUVERTURE ET SOLVABILITÉ ─────────────────────────────────────────────

  # Taux de couverture des intérêts = EBIT / Charges financières (norme > 3)
  def interest_coverage_ratio
    ebit       = income_statement&.ebit
    charges_fi = income_statement&.financial_expenses
    return nil unless ebit && charges_fi&.positive?
    ebit / charges_fi
  end

  # Dettes nettes / EBITDA (norme < 3×)
  def debt_ratio
    nd     = balance_sheet&.net_financial_debt
    ebitda = income_statement&.ebitda_calculated
    return nil unless nd && ebitda&.positive?
    nd / ebitda
  end

  # ── RATIOS BFR ET ROTATIONS ───────────────────────────────────────────────

  # BFR en jours de CA TTC
  def wcr_in_days(vat_rate: 0.20)
    bfr     = balance_sheet&.working_capital_requirement
    revenue = income_statement&.revenue
    return nil unless bfr && revenue&.positive?
    bfr / (revenue * (1 + vat_rate)) * 365
  end

  # Délai de règlement clients (DSO) = Clients / CA TTC × 365
  def days_sales_outstanding(vat_rate: 0.20)
    revenue = income_statement&.revenue
    return nil unless revenue&.positive?
    clients = balance_sheet&.trade_receivables || 0   # nil = 0 client en fin d'exercice
    clients / (revenue * (1 + vat_rate)) * 365
  end

  # Rotation des stocks = Stocks / Coût d'achat × 365
  def days_inventory_outstanding
    stocks    = balance_sheet&.total_inventory
    # Coût d'achat marchandises net (achats - déstockage), fallback matières premières
    cout_achat = begin
      mp  = income_statement&.merchandise_purchases
      var = income_statement&.merchandise_stock_variation
      if mp
        mp + (var || 0)          # achats nets
      else
        income_statement&.raw_materials_purchases
      end
    end
    return nil unless stocks && cout_achat&.positive?
    stocks / cout_achat * 365
  end

  # Délai de règlement fournisseurs (DPO) — fallback merchandise_purchases
  def days_payable_outstanding(vat_rate: 0.20)
    fournisseurs = balance_sheet&.trade_payables
    achats = income_statement&.merchandise_purchases || income_statement&.raw_materials_purchases
    return nil unless fournisseurs && achats&.positive?
    fournisseurs / (achats * (1 + vat_rate)) * 365
  end

  # Cycle de trésorerie = DSO + DIO - DPO (jours)
  def cash_conversion_cycle(vat_rate: 0.20)
    dso = days_sales_outstanding(vat_rate: vat_rate)
    dpo = days_payable_outstanding(vat_rate: vat_rate)
    dio = days_inventory_outstanding
    return nil unless dso && dpo
    dso + (dio || 0) - dpo
  end

  # ── INTENSITÉ CAPITALISTIQUE ──────────────────────────────────────────────
  # Actif économique / Valeur Ajoutée — mesure l'immobilisation par € de VA créée
  def capital_intensity
    ae = balance_sheet&.economic_assets
    va = income_statement&.value_added_calculated
    return nil unless ae && va&.positive?
    ae / va
  end

  # ── PARTAGE DE LA VALEUR AJOUTÉE ─────────────────────────────────────────
  # Retourne un hash { clé => [ratio, montant] } (somme ≤ 1, reste = résidu)
  def va_sharing
    va = income_statement&.value_added_calculated
    return {} unless va&.positive?
    is = income_statement
    taxes_total = (is.taxes_and_duties || 0) + (is.income_tax || 0)
    {
      personnel:      [ (is.personnel_expenses || 0) / va,   is.personnel_expenses    || 0 ],
      etat:           [ taxes_total / va,                     taxes_total               ],
      investissement: [ (is.depreciation_amortization || 0) / va, is.depreciation_amortization || 0 ],
      entreprise:     [ (is.net_income || 0) / va,           is.net_income             || 0 ],
    }
  end

  # ── POLITIQUE D'INVESTISSEMENT ────────────────────────────────────────────
  # Ratio de renouvellement = CAPEX / Dotations amortissements (> 1 = expansion)
  def industrial_policy_ratio
    capex = cash_flow_statement&.capital_expenditure
    amort = cash_flow_statement&.depreciation_amortization || income_statement&.depreciation_amortization
    return nil unless capex && amort&.positive?
    capex / amort
  end

  # ── POINT MORT ────────────────────────────────────────────────────────────

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

  # Marge de sécurité = CA / Point mort - 1 (positif = au-dessus du PM)
  def break_even_distance
    bep     = break_even_point
    revenue = income_statement&.revenue
    return nil unless bep&.positive? && revenue
    revenue / bep - 1
  end

  # Levier opérationnel = MCV / (MCV - Charges fixes) = variation RO% / variation CA%
  def operating_leverage
    vm = variable_margin
    return nil unless vm
    denominator = vm - total_fixed_costs
    return nil unless denominator.positive?
    vm / denominator
  end
end
