class CreateCashFlowStatements < ActiveRecord::Migration[8.1]
  def change
    create_table :cash_flow_statements do |t|
      t.references :financial_report, null: false, foreign_key: true, index: { unique: true }

      # ── CAPACITÉ D'AUTOFINANCEMENT (CAF) ─────────────────────────────────
      t.decimal :net_income,                   precision: 15, scale: 2  # Résultat net
      t.decimal :depreciation_amortization,    precision: 15, scale: 2  # Dotations aux amortissements
      t.decimal :asset_impairment,             precision: 15, scale: 2  # Dépréciations d'actifs immobilisés
      t.decimal :provisions_variation,         precision: 15, scale: 2  # Variation provisions à caractère de réserve
      t.decimal :gains_losses_on_disposals,    precision: 15, scale: 2  # +/- values sur cessions (MV = +, PV = -)
      t.decimal :self_financing_capacity,      precision: 15, scale: 2  # CAF (souvent publiée directement)

      # ── VARIATION DU BFR ─────────────────────────────────────────────────
      t.decimal :inventory_variation,          precision: 15, scale: 2  # Variation stocks
      t.decimal :trade_receivables_variation,  precision: 15, scale: 2  # Variation créances clients
      t.decimal :trade_payables_variation,     precision: 15, scale: 2  # Variation dettes fournisseurs
      t.decimal :other_wcr_variation,          precision: 15, scale: 2  # Variation autres éléments BFR
      t.decimal :total_wcr_variation,          precision: 15, scale: 2  # Variation BFR totale

      # ── FLUX D'EXPLOITATION ───────────────────────────────────────────────
      t.decimal :operating_cash_flow,          precision: 15, scale: 2  # Flux trésorerie d'exploitation (après frais financiers)

      # ── FLUX D'INVESTISSEMENT ─────────────────────────────────────────────
      t.decimal :asset_disposals,              precision: 15, scale: 2  # Produits de cessions d'actifs
      t.decimal :capital_expenditure,          precision: 15, scale: 2  # Investissements (CAPEX)
      t.decimal :investing_cash_flow,          precision: 15, scale: 2  # Flux d'investissement net

      # ── FLUX DE TRÉSORERIE DISPONIBLE ────────────────────────────────────
      t.decimal :free_cash_flow,               precision: 15, scale: 2  # Flux trésorerie disponible après frais financiers

      # ── FLUX DE FINANCEMENT ───────────────────────────────────────────────
      t.decimal :capital_increase,             precision: 15, scale: 2  # Augmentation de capital
      t.decimal :dividends_paid,               precision: 15, scale: 2  # Dividendes versés

      # ── ENDETTEMENT NET ───────────────────────────────────────────────────
      t.decimal :net_debt_change,              precision: 15, scale: 2  # Variation endettement net (- = désendettement)
      t.decimal :net_debt_opening,             precision: 15, scale: 2  # Endettement net début d'exercice
      t.decimal :net_debt_closing,             precision: 15, scale: 2  # Endettement net fin d'exercice

      t.timestamps
    end

  end
end
