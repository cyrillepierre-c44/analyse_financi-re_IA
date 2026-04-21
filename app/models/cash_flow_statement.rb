class CashFlowStatement < ApplicationRecord
  belongs_to :financial_report

  # ── CAF (méthode additive) ─────────────────────────────────────────────
  # CAF = Résultat net + Dotations amortissements + Dépréciations
  #       + Variation provisions +/- MV/PV cessions
  def self_financing_capacity_calculated
    return self_financing_capacity if self_financing_capacity.present?
    return nil unless net_income
    (net_income || 0) +
    (depreciation_amortization || 0) +
    (asset_impairment || 0) +
    (provisions_variation || 0) +
    (gains_losses_on_disposals || 0)
  end

  # ── FLUX D'EXPLOITATION après frais financiers ────────────────────────
  # = CAF - Variation BFR
  def operating_cash_flow_calculated
    return operating_cash_flow if operating_cash_flow.present?
    caf = self_financing_capacity_calculated
    return nil unless caf && total_wcr_variation
    caf - total_wcr_variation
  end

  # ── FLUX DE TRÉSORERIE DISPONIBLE ─────────────────────────────────────
  # = Flux exploitation + Flux investissement
  def free_cash_flow_calculated
    return free_cash_flow if free_cash_flow.present?
    op = operating_cash_flow_calculated
    return nil unless op && investing_cash_flow
    op + investing_cash_flow
  end
end
