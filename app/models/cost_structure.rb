class CostStructure < ApplicationRecord
  belongs_to :financial_report

  enum :cost_category, {
    cost_of_sales:          0,  # Coût des ventes
    distribution_marketing: 1,  # Coûts distribution & marketing
    administrative:         2,  # Coûts administratifs
    total:                  3   # Total
  }

  # ── ANALYSE DU POINT MORT ─────────────────────────────────────────────

  # Marge sur coûts variables = CA - Charges variables (calculé au niveau du rapport)
  # Taux de marge sur coûts variables = MCV / CA
  # Point mort (€) = Charges fixes / Taux MCV
  # Levier opérationnel = MCV / (MCV - Charges fixes)

  def total_costs
    (fixed_costs || 0) + (variable_costs || 0)
  end

  # Calculs disponibles au niveau FinancialReport (agrège tous les cost_structures)
end
