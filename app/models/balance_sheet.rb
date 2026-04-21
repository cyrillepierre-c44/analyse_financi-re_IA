class BalanceSheet < ApplicationRecord
  belongs_to :financial_report

  # ── BILAN ÉCONOMIQUE ──────────────────────────────────────────────────

  # BFR = Stocks + Créances d'exploitation - Dettes d'exploitation
  def working_capital_requirement
    stocks = total_inventory || 0
    creances = (trade_receivables || 0) +
               (customer_advances_paid || 0) +
               (other_operating_receivables || 0) +
               (prepaid_expenses || 0) +
               (discounted_bills_not_due || 0)
    dettes = (trade_payables || 0) +
             (customer_advances_received || 0) +
             (tax_and_social_liabilities || 0) +
             (other_operating_liabilities || 0) +
             (deferred_income || 0)
    stocks + creances - dettes
  end

  # Actif économique = Immobilisations nettes + BFR
  def economic_assets
    return nil unless total_fixed_assets_net
    total_fixed_assets_net + working_capital_requirement
  end

  # Endettement net = Dettes financières - Trésorerie (disponibilités + VMP)
  def net_financial_debt
    dettes = (lt_financial_debt || 0) + (st_financial_debt || 0) + (finance_lease_debt || 0)
    tresorerie = (cash_and_equivalents || 0) + (short_term_investments || 0)
    dettes - tresorerie
  end

  # ── RATIOS D'INVESTISSEMENT ───────────────────────────────────────────

  # Ratio état outil industriel = Immo nettes / Immo brutes
  def industrial_tool_ratio
    return nil unless total_fixed_assets_gross&.positive?
    total_fixed_assets_net / total_fixed_assets_gross
  end

  # ── RATIOS DE LIQUIDITÉ ───────────────────────────────────────────────

  def current_liabilities
    (st_financial_debt || 0) +
    (trade_payables || 0) +
    (customer_advances_received || 0) +
    (tax_and_social_liabilities || 0) +
    (other_operating_liabilities || 0) +
    (deferred_income || 0)
  end

  # Ratio de liquidité générale = Actif circulant / Passif exigible CT
  def general_liquidity_ratio
    return nil unless current_liabilities.positive?
    (total_current_assets || 0) / current_liabilities
  end

  # Ratio de liquidité réduite = (Actif circulant - Stocks) / Passif exigible CT
  def reduced_liquidity_ratio
    return nil unless current_liabilities.positive?
    ((total_current_assets || 0) - (total_inventory || 0)) / current_liabilities
  end

  # Ratio de liquidité immédiate = (Disponibilités + VMP) / Passif exigible CT
  def immediate_liquidity_ratio
    return nil unless current_liabilities.positive?
    ((cash_and_equivalents || 0) + (short_term_investments || 0)) / current_liabilities
  end

  # ── RATIOS DE STRUCTURE ───────────────────────────────────────────────

  # Ratio d'autonomie financière = Capitaux propres / Total passif
  def financial_autonomy_ratio
    return nil unless total_equity_and_liabilities&.positive?
    (total_equity || 0) / total_equity_and_liabilities
  end

  # Levier financier = Dettes financières nettes / Capitaux propres
  def financial_leverage
    return nil unless total_equity&.positive?
    net_financial_debt / total_equity
  end
end
