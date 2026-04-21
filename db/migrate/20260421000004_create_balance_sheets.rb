class CreateBalanceSheets < ActiveRecord::Migration[8.1]
  def change
    create_table :balance_sheets do |t|
      t.references :financial_report, null: false, foreign_key: true, index: { unique: true }

      # ── ACTIF IMMOBILISÉ ─────────────────────────────────────────────────
      t.decimal :intangible_assets_gross,      precision: 15, scale: 2  # Immo incorporelles brutes
      t.decimal :intangible_assets_net,        precision: 15, scale: 2  # Immo incorporelles nettes
      t.decimal :tangible_assets_gross,        precision: 15, scale: 2  # Immo corporelles brutes
      t.decimal :tangible_assets_net,          precision: 15, scale: 2  # Immo corporelles nettes
      t.decimal :financial_assets_gross,       precision: 15, scale: 2  # Immo financières brutes
      t.decimal :financial_assets_net,         precision: 15, scale: 2  # Immo financières nettes
      t.decimal :total_fixed_assets_gross,     precision: 15, scale: 2  # Total immo brutes
      t.decimal :total_fixed_assets_net,       precision: 15, scale: 2  # Total immo nettes
      t.decimal :goodwill,                     precision: 15, scale: 2  # Écart d'acquisition / goodwill
      t.decimal :equity_method_investments,    precision: 15, scale: 2  # Titres mis en équivalence

      # ── ACTIF CIRCULANT — STOCKS ─────────────────────────────────────────
      t.decimal :raw_materials_inventory,      precision: 15, scale: 2  # Stocks matières premières
      t.decimal :merchandise_inventory,        precision: 15, scale: 2  # Stocks marchandises
      t.decimal :wip_inventory,                precision: 15, scale: 2  # Stocks produits en cours / semi-finis
      t.decimal :finished_goods_inventory,     precision: 15, scale: 2  # Stocks produits finis
      t.decimal :total_inventory,              precision: 15, scale: 2  # Total stocks

      # ── ACTIF CIRCULANT — CRÉANCES ───────────────────────────────────────
      t.decimal :trade_receivables,            precision: 15, scale: 2  # Clients & comptes rattachés
      t.decimal :customer_advances_paid,       precision: 15, scale: 2  # Avances & acomptes versés
      t.decimal :other_operating_receivables,  precision: 15, scale: 2  # Autres créances d'exploitation
      t.decimal :prepaid_expenses,             precision: 15, scale: 2  # Charges constatées d'avance
      t.decimal :discounted_bills_not_due,     precision: 15, scale: 2  # Effets escomptés non échus

      # ── ACTIF CIRCULANT — TRÉSORERIE ─────────────────────────────────────
      t.decimal :short_term_investments,       precision: 15, scale: 2  # Valeurs mobilières de placement (VMP)
      t.decimal :cash_and_equivalents,         precision: 15, scale: 2  # Disponibilités

      # ── TOTAUX ACTIF ─────────────────────────────────────────────────────
      t.decimal :total_current_assets,         precision: 15, scale: 2  # Total actif circulant
      t.decimal :total_assets,                 precision: 15, scale: 2  # Total actif

      # ── CAPITAUX PROPRES ─────────────────────────────────────────────────
      t.decimal :share_capital,                precision: 15, scale: 2  # Capital social
      t.decimal :share_premium,                precision: 15, scale: 2  # Prime d'émission
      t.decimal :reserves,                     precision: 15, scale: 2  # Réserves
      t.decimal :retained_earnings_bf,         precision: 15, scale: 2  # Report à nouveau
      t.decimal :net_income_period,            precision: 15, scale: 2  # Résultat de l'exercice
      t.decimal :total_equity,                 precision: 15, scale: 2  # Capitaux propres
      t.decimal :minority_interests,           precision: 15, scale: 2  # Intérêts minoritaires (consolidés)

      # ── DETTES À LONG TERME ───────────────────────────────────────────────
      t.decimal :provisions_for_risks,         precision: 15, scale: 2  # Provisions pour risques & charges
      t.decimal :lt_financial_debt,            precision: 15, scale: 2  # Emprunts & dettes financières > 1 an

      # ── DETTES À COURT TERME ─────────────────────────────────────────────
      t.decimal :st_financial_debt,            precision: 15, scale: 2  # Dettes bancaires < 1 an
      t.decimal :finance_lease_debt,           precision: 15, scale: 2  # Crédit-bail
      t.decimal :trade_payables,               precision: 15, scale: 2  # Dettes fournisseurs
      t.decimal :customer_advances_received,   precision: 15, scale: 2  # Avances reçues clients
      t.decimal :tax_and_social_liabilities,   precision: 15, scale: 2  # Dettes fiscales & sociales
      t.decimal :other_operating_liabilities,  precision: 15, scale: 2  # Autres dettes d'exploitation
      t.decimal :deferred_income,              precision: 15, scale: 2  # Produits constatés d'avance

      # ── TOTAUX PASSIF ─────────────────────────────────────────────────────
      t.decimal :total_liabilities,            precision: 15, scale: 2  # Total dettes
      t.decimal :total_equity_and_liabilities, precision: 15, scale: 2  # Total passif

      t.timestamps
    end

  end
end
