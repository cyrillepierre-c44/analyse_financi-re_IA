class CreateIncomeStatements < ActiveRecord::Migration[8.1]
  def change
    create_table :income_statements do |t|
      t.references :financial_report, null: false, foreign_key: true, index: { unique: true }

      # ── COMMUN (par nature ET par fonction) ──────────────────────────────
      t.decimal :revenue,                    precision: 15, scale: 2  # Chiffre d'affaires
      t.decimal :ebit,                       precision: 15, scale: 2  # Résultat d'exploitation / résultat opérationnel
      t.decimal :financial_income,           precision: 15, scale: 2  # Produits financiers
      t.decimal :financial_expenses,         precision: 15, scale: 2  # Charges financières
      t.decimal :current_result,             precision: 15, scale: 2  # Résultat courant avant impôt
      t.decimal :exceptional_income,         precision: 15, scale: 2  # Produits exceptionnels / non récurrents
      t.decimal :exceptional_expenses,       precision: 15, scale: 2  # Charges exceptionnelles / non récurrentes
      t.decimal :income_tax,                 precision: 15, scale: 2  # Impôt sur les sociétés
      t.decimal :net_income,                 precision: 15, scale: 2  # Résultat net
      t.decimal :dividends_paid,             precision: 15, scale: 2  # Dividendes versés
      t.decimal :retained_earnings,          precision: 15, scale: 2  # Résultat non distribué
      t.decimal :minority_interests,         precision: 15, scale: 2  # Intérêts minoritaires (consolidés)

      # ── PAR FONCTION (IFRS / international) ──────────────────────────────
      t.decimal :cost_of_sales,                    precision: 15, scale: 2  # Coût des ventes
      t.decimal :gross_margin,                     precision: 15, scale: 2  # Marge brute
      t.decimal :distribution_marketing_costs,     precision: 15, scale: 2  # Coûts distribution & marketing
      t.decimal :administrative_costs,             precision: 15, scale: 2  # Coûts administratifs

      # ── PAR NATURE (PCG français) ─────────────────────────────────────────
      t.decimal :merchandise_sales,                precision: 15, scale: 2  # Ventes de marchandises
      t.decimal :merchandise_purchases,            precision: 15, scale: 2  # Achats de marchandises
      t.decimal :merchandise_stock_variation,      precision: 15, scale: 2  # Variation stocks marchandises
      t.decimal :commercial_margin,                precision: 15, scale: 2  # Marge commerciale
      t.decimal :production_sold,                  precision: 15, scale: 2  # Production vendue
      t.decimal :production_stored,                precision: 15, scale: 2  # Production stockée
      t.decimal :capitalized_production,           precision: 15, scale: 2  # Production immobilisée
      t.decimal :operating_subsidies,              precision: 15, scale: 2  # Subventions d'exploitation
      t.decimal :raw_materials_purchases,          precision: 15, scale: 2  # Achats matières premières
      t.decimal :raw_materials_stock_variation,    precision: 15, scale: 2  # Variation stocks MP
      t.decimal :other_external_expenses,          precision: 15, scale: 2  # Autres achats & charges externes
      t.decimal :taxes_and_duties,                 precision: 15, scale: 2  # Impôts, taxes & versements
      t.decimal :personnel_expenses,               precision: 15, scale: 2  # Charges de personnel
      t.decimal :depreciation_amortization,        precision: 15, scale: 2  # Dotations aux amortissements
      t.decimal :asset_impairment,                 precision: 15, scale: 2  # Dépréciations d'actifs immobilisés
      t.decimal :provisions_charge,                precision: 15, scale: 2  # Dotations aux provisions
      t.decimal :other_operating_expenses,         precision: 15, scale: 2  # Autres charges d'exploitation
      t.decimal :other_operating_income,           precision: 15, scale: 2  # Autres produits d'exploitation
      t.decimal :value_added,                      precision: 15, scale: 2  # Valeur ajoutée (VA)
      t.decimal :ebitda,                           precision: 15, scale: 2  # Excédent brut d'exploitation (EBE)

      t.timestamps
    end

  end
end
