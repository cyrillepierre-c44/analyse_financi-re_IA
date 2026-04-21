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
  def value_added_calculated
    return value_added if value_added.present?
    return nil unless production_total && raw_materials_purchases && other_external_expenses
    cm = commercial_margin_calculated || 0
    consommations = (raw_materials_purchases || 0) + (raw_materials_stock_variation || 0) + (other_external_expenses || 0)
    cm + production_total - consommations
  end

  # EBE = VA + Subventions d'exploitation - Charges personnel - Impôts & taxes
  def ebitda_calculated
    return ebitda if ebitda.present?
    va = value_added_calculated
    return nil unless va && personnel_expenses
    va + (operating_subsidies || 0) - (personnel_expenses || 0) - (taxes_and_duties || 0)
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

  def result_financier
    return nil unless financial_income && financial_expenses
    financial_income - financial_expenses
  end
end
