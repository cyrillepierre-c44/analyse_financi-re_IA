# Seeds : Centaur Bike — exercices 2022 et 2023
# Données extraites directement des plaquettes comptables (expert-comptable Mathieu Partamian, QINTENS)

puts "Création de la société Centaur Bike..."

company = Company.find_or_create_by!(name: "Centaur Bike") do |c|
  c.siren              = "892208018"
  c.sector             = "Vélo électrique"
  c.country            = "FR"
  c.accounting_standard = :pcg
  c.is_consolidated    = false
  c.currency           = "EUR"
end

puts "  → #{company.name} (id #{company.id})"

# ─────────────────────────────────────────────────────────────────────────────
# EXERCICE 2022  (01/01/2022 – 31/12/2022)
# ─────────────────────────────────────────────────────────────────────────────
puts "\nExercice 2022..."

report_2022 = company.financial_reports.find_or_initialize_by(fiscal_year: 2022)
report_2022.assign_attributes(
  period_end_date:      Date.new(2022, 12, 31),
  period_type:          :annual,
  accounting_standard:  :pcg,
  is_consolidated:      false,
  income_format:        :nature,
  source_file:          "2022-12 CENTAUR BIKE-Plaquette.pdf"
)
report_2022.save!

# ── Compte de résultat 2022 ───────────────────────────────────────────────────
is_2022 = report_2022.income_statement || report_2022.build_income_statement
is_2022.assign_attributes(
  # Produits
  revenue:                        251_945.33,
  merchandise_sales:              251_887.00,
  production_sold:                     58.00,
  other_operating_income:           1_703.00,   # Autres produits (produits gestion courante + transfert charges)
  operating_subsidies:                  0.00,   # Pas de subvention en 2022 (celle de 2021 = 2 143€)

  # Charges — par nature (PCG)
  merchandise_purchases:          156_393.00,
  merchandise_stock_variation:     -2_387.00,   # Variation de stock marchandises (négatif = déstockage)
  other_external_expenses:         36_946.00,   # Autres achats et charges externes
  taxes_and_duties:                   321.00,   # Impôts, taxes et versements assimilés
  personnel_expenses:                   0.00,   # Pas de salarié en 2022
  depreciation_amortization:        4_308.00,   # Dotations aux amortissements
  other_operating_expenses:             3.00,   # Autres charges de gestion courante

  # SIG intermédiaires
  commercial_margin:               97_881.00,   # Ventes march. - (Achats march. + Var. stocks) = 251887 - (156393-2387)
  # value_added calculée : Marge commerciale + Prod. vendue - Autres achats et ch. ext. - Impôts
  # value_added: → calculée en Ruby

  # Résultats
  ebit:                            58_064.00,   # Résultat d'exploitation
  financial_income:                     0.00,
  exceptional_income:               1_000.00,   # Produit exceptionnel
  financial_expenses:                 401.00,   # Intérêts sur emprunts
  exceptional_expenses:                 0.00,
  current_result:                  58_663.00,   # Résultat avant IS (= 58064 + 1000 - 401)
  income_tax:                       9_641.00,   # IS (10654 - crédit d'impôt mécénat 1013)
  net_income:                      49_022.10
)
is_2022.save!

# ── Bilan 2022 ────────────────────────────────────────────────────────────────
bs_2022 = report_2022.balance_sheet || report_2022.build_balance_sheet
bs_2022.assign_attributes(
  # ── ACTIF IMMOBILISÉ ──────────────────────────────────────────────────────
  goodwill:                        25_000.00,   # Fonds commercial (droit au bail)

  # Immobilisations incorporelles (hors fonds commercial) : frais établissement + marques
  intangible_assets_gross:          3_149.00,
  intangible_assets_net:            1_367.00,

  # Immobilisations corporelles : outillage + aménagements + matériel transport + bureau + mobilier
  tangible_assets_gross:           16_914.00,
  tangible_assets_net:             10_858.00,

  # Immobilisations financières : dépôts et cautionnements + retenue garantie
  financial_assets_gross:           2_633.00,
  financial_assets_net:             2_633.00,

  total_fixed_assets_gross:        47_696.00,   # Actif immobilisé brut
  total_fixed_assets_net:          39_858.00,   # Actif immobilisé net

  # ── ACTIF CIRCULANT ───────────────────────────────────────────────────────
  merchandise_inventory:           27_830.00,   # Stock marchandises
  total_inventory:                 27_830.00,

  trade_receivables:                5_819.00,   # Clients et comptes rattachés
  other_operating_receivables:        251.00,   # Autres créances (TVA déductible + TVA s/fres)

  short_term_investments:          20_000.00,   # Valeurs mobilières de placement (Compte Optiplus)
  cash_and_equivalents:            28_029.00,   # Banques (28024) + Caisse (5)

  total_current_assets:            81_929.00,

  total_assets:                   121_787.44,

  # ── CAPITAUX PROPRES ──────────────────────────────────────────────────────
  share_capital:                   10_000.00,
  reserves:                             0.00,
  retained_earnings_bf:              -735.00,   # Report à nouveau (solde débiteur)
  net_income_period:               49_022.10,
  total_equity:                    58_287.00,

  # ── DETTES ────────────────────────────────────────────────────────────────
  lt_financial_debt:               41_745.00,   # Emprunts BNP + BP + France Active

  trade_payables:                   9_265.00,   # Fournisseurs et comptes rattachés

  # Autres dettes : IS (9641) + TVA décaissée (1817) + TVA collectée (970) + C/C associé (62)
  tax_and_social_liabilities:      12_428.00,   # IS + TVA (9641+1817+970)
  other_operating_liabilities:         62.00,   # C/C M. Pierre Cyrille

  total_liabilities:               63_501.00,

  total_equity_and_liabilities:   121_787.44
)
bs_2022.save!

puts "  → Bilan et compte de résultat 2022 enregistrés"


# ─────────────────────────────────────────────────────────────────────────────
# EXERCICE 2023  (01/01/2023 – 31/12/2023)
# ─────────────────────────────────────────────────────────────────────────────
puts "\nExercice 2023..."

report_2023 = company.financial_reports.find_or_initialize_by(fiscal_year: 2023)
report_2023.assign_attributes(
  period_end_date:      Date.new(2023, 12, 31),
  period_type:          :annual,
  accounting_standard:  :pcg,
  is_consolidated:      false,
  income_format:        :nature,
  source_file:          "2023-12 CENTAUR BIKE-Plaquette.pdf"
)
report_2023.save!

# ── Compte de résultat 2023 ───────────────────────────────────────────────────
is_2023 = report_2023.income_statement || report_2023.build_income_statement
is_2023.assign_attributes(
  # Produits
  revenue:                        183_616.07,
  merchandise_sales:              183_574.00,
  production_sold:                     42.00,
  other_operating_income:             102.00,   # Produits de gestion courante + transfert charges
  operating_subsidies:                  0.00,

  # Charges — par nature (PCG)
  merchandise_purchases:           88_228.00,
  merchandise_stock_variation:      9_748.00,   # Positif = augmentation des achats nets (déstockage)
  other_external_expenses:         32_055.00,   # Autres achats et charges externes
  taxes_and_duties:                 1_348.00,   # Impôts, taxes et versements assimilés
  personnel_expenses:              38_555.00,   # Salaires (28076) + Charges sociales (10479)
  depreciation_amortization:        4_477.00,   # Dotations aux amortissements
  other_operating_expenses:            28.00,   # Autres charges de gestion courante

  # SIG intermédiaires
  commercial_margin:               85_598.00,   # Ventes march. - (Achats march. + Var. stocks) = 183574 - (88228+9748)

  # Résultats
  ebit:                             9_280.00,   # Résultat d'exploitation
  financial_income:                    39.00,   # Produits financiers
  exceptional_income:                   0.00,
  financial_expenses:                 342.00,   # Intérêts sur emprunts
  exceptional_expenses:                 0.00,
  current_result:                   8_977.00,   # Résultat avant IS
  income_tax:                       1_347.00,
  net_income:                       7_630.27
)
is_2023.save!

# ── Bilan 2023 ────────────────────────────────────────────────────────────────
bs_2023 = report_2023.balance_sheet || report_2023.build_balance_sheet
bs_2023.assign_attributes(
  # ── ACTIF IMMOBILISÉ ──────────────────────────────────────────────────────
  goodwill:                        25_000.00,   # Fonds commercial (droit au bail)

  intangible_assets_gross:          3_149.00,
  intangible_assets_net:              493.00,

  # Immo corporelles : +matériel transport (6143 acquis en 2023)
  tangible_assets_gross:           22_228.00,
  tangible_assets_net:             12_570.00,

  financial_assets_gross:           2_633.00,
  financial_assets_net:             2_633.00,

  total_fixed_assets_gross:        53_010.00,
  total_fixed_assets_net:          40_695.00,

  # ── ACTIF CIRCULANT ───────────────────────────────────────────────────────
  merchandise_inventory:           18_082.00,   # Stock marchandises (baisse)
  total_inventory:                 18_082.00,

  customer_advances_paid:           3_148.00,   # Avances et acomptes versés sur commandes (Fourn. acomptes)
  trade_receivables:                6_127.00,   # Clients et comptes rattachés
  # Autres créances : IS à récupérer (1317) + TVA déductible (234) + TVA s/fres (246)
  other_operating_receivables:      1_797.00,

  short_term_investments:              39.00,   # VMP (Compte Optiplus résiduel)
  cash_and_equivalents:            35_406.00,   # Banques (35233) + Caisse (173)
  prepaid_expenses:                 3_419.00,   # Charges constatées d'avance

  total_current_assets:            68_018.00,

  total_assets:                   108_713.31,

  # ── CAPITAUX PROPRES ──────────────────────────────────────────────────────
  share_capital:                   10_000.00,
  # Réserve légale (1000) + Autres réserves (47287) = affectation résultat 2022
  reserves:                        48_287.00,
  retained_earnings_bf:                 0.00,   # Report à nouveau soldé
  net_income_period:                7_630.27,
  total_equity:                    65_917.00,

  # ── DETTES ────────────────────────────────────────────────────────────────
  lt_financial_debt:               28_543.00,   # Emprunts BNP + BP + France Active (remboursement continu)

  trade_payables:                   5_336.00,   # Fournisseurs et comptes rattachés

  # Autres dettes : social (URSSAF 1628 + mutuelle 46 + prévoyance 338 + taxe apprent. 25 + PAS 132)
  #   + TVA décaissée (2973) + TVA collectée (1062) + C/C associé (2561) + assurance (152)
  tax_and_social_liabilities:       6_204.00,   # Charges sociales (2169) + TVA (4035)
  other_operating_liabilities:      2_713.00,   # C/C Cyrille (2561) + assurance (152)

  total_liabilities:               42_796.00,

  total_equity_and_liabilities:   108_713.31
)
bs_2023.save!

puts "  → Bilan et compte de résultat 2023 enregistrés"


# ─────────────────────────────────────────────────────────────────────────────
# RÉSUMÉ DES INDICATEURS CALCULÉS
# ─────────────────────────────────────────────────────────────────────────────
puts "\n" + "=" * 60
puts "CENTAUR BIKE — Indicateurs financiers"
puts "=" * 60

[report_2022, report_2023].each do |r|
  puts "\n── Exercice #{r.fiscal_year} ──────────────────────────────────"
  is = r.income_statement
  bs = r.balance_sheet

  puts "  CA               : #{format('%.0f', is.revenue)} €"
  puts "  Marge commerciale: #{format('%.0f', is.commercial_margin)} € (#{format('%.1f', is.commercial_margin / is.revenue * 100)} %)" if is.commercial_margin
  puts "  EBIT             : #{format('%.0f', is.ebit)} € (marge #{format('%.1f', is.ebit_margin * 100)} %)" if is.ebit && is.respond_to?(:ebit_margin) && is.ebit_margin
  puts "  Résultat net     : #{format('%.0f', is.net_income)} € (marge #{format('%.1f', is.net_margin * 100)} %)" if is.net_income && is.respond_to?(:net_margin) && is.net_margin

  puts "  Total actif      : #{format('%.0f', bs.total_assets)} €"
  puts "  Capitaux propres : #{format('%.0f', bs.total_equity)} €"

  if bs.respond_to?(:working_capital_requirement)
    bfr = bs.working_capital_requirement
    puts "  BFR              : #{format('%.0f', bfr)} €" if bfr
  end

  if bs.respond_to?(:net_financial_debt)
    nfd = bs.net_financial_debt
    puts "  Dette nette      : #{format('%.0f', nfd)} €" if nfd
  end

  if r.respond_to?(:economic_return) && r.economic_return
    puts "  Re (EBIT/actif)  : #{format('%.1f', r.economic_return * 100)} %"
  end

  if r.respond_to?(:return_on_equity) && r.return_on_equity
    puts "  Rcp (RN/CP)      : #{format('%.1f', r.return_on_equity * 100)} %"
  end
rescue => e
  puts "  [erreur indicateurs : #{e.message}]"
end

puts "\nSeeds terminés."
