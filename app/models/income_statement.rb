class IncomeStatement < ApplicationRecord
  belongs_to :financial_report

  # ── SOLDES INTERMÉDIAIRES DE GESTION (SIG) ─────────────────────────────

  # Marge commerciale = Ventes marchandises - Coût d'achat marchandises
  def commercial_margin_calculated
    return commercial_margin if commercial_margin.present?
    return nil unless merchandise_sales && merchandise_purchases && merchandise_stock_variation
    merchandise_sales - merchandise_purchases - merchandise_stock_variation
  end

  # Production de l'exercice = Production vendue + stockée + immobilisée
  def production_total
    return nil unless production_sold
    (production_sold || 0) + (production_stored || 0) + (capitalized_production || 0)
  end

  # Valeur Ajoutée = Marge commerciale + Production - Consommations externes
  # Pour les sociétés commerciales (sans matières premières) raw_materials_purchases est nil → traité comme 0
  def value_added_calculated
    return value_added if value_added.present?
    return nil unless other_external_expenses
    cm = commercial_margin_calculated || 0
    prod = production_total || 0
    consommations = (raw_materials_purchases || 0) + (raw_materials_stock_variation || 0) + other_external_expenses
    cm + prod - consommations
  end

  # EBE = VA + Subventions d'exploitation - Charges personnel - Impôts & taxes
  # En l'absence de charges personnel (gérant non salarié), on accepte nil → 0
  # Fallback IFRS "fonction" : EBITDA = EBIT + Dotations aux amortissements
  def ebitda_calculated
    return ebitda if ebitda.present?
    va = value_added_calculated
    return va + (operating_subsidies || 0) - (personnel_expenses || 0) - (taxes_and_duties || 0) if va
    return ebit + depreciation_amortization if ebit && depreciation_amortization
    # Fallback : DAP depuis le tableau de flux (IFRS "fonction" — DAP non isolée dans l'IS)
    cfs_dap = financial_report.cash_flow_statement&.depreciation_amortization
    return ebit + cfs_dap if ebit && cfs_dap
    nil
  end

  # ── RATIOS D'ANALYSE DES MARGES ────────────────────────────────────────

  def gross_margin_rate
    return nil unless revenue&.positive?
    gross_margin_value = gross_margin || ebitda_calculated
    return nil unless gross_margin_value
    gross_margin_value / revenue
  end

  def ebitda_margin
    return nil unless revenue&.positive? && ebitda_calculated
    ebitda_calculated / revenue
  end

  def ebit_margin
    return nil unless revenue&.positive? && ebit
    ebit / revenue
  end

  def net_margin
    return nil unless revenue&.positive? && net_income
    net_income / revenue
  end

  # ── ANALYSE DU POINT MORT ─────────────────────────────────────────────
  # (nécessite les données de cost_structures)

  # IFRS : financial_expenses = coût endettement NET (peut être négatif si tréso nette)
  # → result_financier = -financial_expenses (on n'exige pas financial_income)
  def result_financier
    return nil if financial_income.nil? && financial_expenses.nil?
    (financial_income || 0) - (financial_expenses || 0)
  end
end
