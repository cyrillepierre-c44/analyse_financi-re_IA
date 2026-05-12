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

# ─────────────────────────────────────────────────────────────────────────────
# QUESTIONS — DIAGNOSTIC RAPIDE Q&A
# Une banque de questions communes à toutes les entreprises.
# L'IA sélectionne la/les bonne(s) réponse(s) selon les données financières.
# ─────────────────────────────────────────────────────────────────────────────
puts "\nChargement des questions Q&A..."

# Remise à zéro des questions (idempotent via position)
# Pour ajouter une question : copier un bloc et incrémenter la position.
QUESTIONS = [
  {
    position:    1,
    text:        "Quel est le taux de croissance moyen annuel (TCAM) du chiffre d'affaires sur la période analysée ?",
    answer_type: "numerical",
    options:     ["%"]   # unité affichée après la valeur calculée
  },
  {
    position:    2,
    text:        "Cette évolution des ventes s'explique-t-elle principalement par :",
    answer_type: "single",
    options:     [
      "Des variations du périmètre du groupe.",
      "Une baisse du prix de vente moyen, et une hausse corrélative des ventes en volume.",
      "Une hausse du prix de vente moyen, et une baisse corrélative des ventes en volume.",
      "Une hausse du prix de vente moyen, et une hausse corrélative des ventes en volume."
    ]
  },
  {
    position:    3,
    text:        "Le secteur du Champagne depuis 1998 vous parait-il :",
    answer_type: "single",
    options:     [
      "Cyclique, mais en croissance en volume.",
      "Cyclique, mais stagnant en volume.",
      "Non cyclique, mais en croissance en volume.",
      "Non cyclique, et stagnant en volume."
    ]
  },
  {
    position:    4,
    text:        "L'activité de Laurent-Perrier est-elle ?",
    answer_type: "single",
    options:     [
      "Saisonnière pour les ventes, mais pas pour ses achats.",
      "Saisonnière pour les ventes, et pour ses achats.",
      "Ni saisonnière pour les ventes, ni pour ses achats.",
      "Pas saisonnière pour les ventes, mais saisonnière pour ses achats."
    ]
  },
  {
    position:    5,
    text:        "Que révèle l'évolution du prix de vente moyen par bouteille et du prix du raisin en 2021-2022 à 2023-2024 ?",
    answer_type: "single",
    options:     [
      "Rien.",
      "Un effet de ciseau positif.",
      "Un effet de ciseau négatif.",
      "Un effet point mort positif."
    ]
  },
  {
    position:    6,
    text:        "Que révèle l'évolution du prix de vente moyen par bouteille et du prix du raisin en 2023-2024 à 2024-2025 ?",
    answer_type: "single",
    options:     [
      "Rien.",
      "Un effet de ciseau positif.",
      "Un effet de ciseau négatif.",
      "Un effet point mort positif."
    ]
  },
  {
    position:    7,
    text:        "À votre avis, la marge brute par bouteille devrait :",
    answer_type: "single",
    options:     [
      "baisser en 2025-2026, car Laurent-Perrier utilise des vins de différentes années précédentes pour produire ses champagnes, conduisant à une hausse du prix de revient de la bouteille malgré un ralentissement de la hausse du prix des raisins.",
      "rester stable en 2025-2026, car la phase d'inflation forte de 2022-2023 est passée.",
      "augmenter en 2025-2026, grâce au retour de l'inflation due à la flambée des prix des énergies fossiles.",
      "C'est bien difficile à dire."
    ]
  },
  {
    position:    8,
    text:        "En supposant que les coûts des ventes soient intégralement des coûts variables, et que tous les autres coûts d'exploitation soient des coûts fixes, calculez le point mort d'exploitation de la première année en millions d'euros, sans chiffre après la virgule. Formule : Charges fixes = Marge brute − EBIT. Taux MCV = Marge brute / CA. Point mort = Charges fixes / Taux MCV.",
    answer_type: "numerical",
    options:     ["M€"]
  },
  {
    position:    9,
    text:        "À quel pourcentage Laurent-Perrier se situe-t-il au-dessus de son point mort d'exploitation la dernière année ? (répondre sans chiffre après la virgule, ex : 15,3 % → 15)",
    answer_type: "numerical",
    options:     ["%"]
  },
  {
    position:    10,
    text:        "Êtes-vous surpris de ce dernier résultat ?",
    answer_type: "single",
    options:     [
      "Non car Laurent-Perrier connaît une baisse de ses ventes.",
      "Non car Laurent-Perrier a une marge d'exploitation assez faible.",
      "Non car Laurent-Perrier a une marge d'exploitation forte.",
      "Non car Laurent-Perrier est une entreprise saisonnière."
    ]
  },
  {
    position:    11,
    text:        "Que pensez-vous du taux d'impôt sur les sociétés apparent, rapport de l'impôt sur les sociétés divisé par le résultat avant impôt en 2024-2025 ?",
    answer_type: "single",
    options:     [
      "À 25,9 %, il me parait logique.",
      "À 8 %, il me parait bien bas. Laurent-Perrier ferait-il de l'évasion fiscale ou de l'optimisation agressive ?",
      "À 25,9 %, il me parait bien bas. Laurent-Perrier ferait-il de l'évasion fiscale ou de l'optimisation agressive ?",
      "À 18 %, il me parait logique."
    ]
  },
  {
    position:    12,
    text:        "À votre avis, le BFR, tel qu'il apparait dans les comptes au 31 mars,",
    answer_type: "multiple",
    options:     [
      "est plus bas que celui du 31 décembre, car les clients ont payé les ventes de Noël et du 1er de l'an.",
      "est plus bas que celui du 30 septembre, car la nouvelle récolte ne vient pas de juste rentrer.",
      "est probablement plus haut que celui au 30 juin qui aurait enregistré une baisse de stocks de produits finis par rapport au 31 mars, sans avoir rentré une nouvelle récolte qui n'intervient qu'en septembre.",
      "C'est bien difficile à dire compte tenu du caractère cyclique du secteur du Champagne."
    ]
  },
  {
    position:    13,
    text:        "Calculez le ratio du BFR d'exploitation en jours de chiffre d'affaires pour 2021-2022. Vous vous interrogerez sur la pertinence de prendre en compte un taux de TVA dans ce cas, compte tenu de la part des stocks dans le BFR et du fait que la TVA (au taux de 20%) ne s'applique pas aux ventes à l'export. Sans chiffre après la virgule.",
    answer_type: "numerical",
    options:     ["jours"]
  },
  {
    position:    14,
    text:        "Calculez le délai de paiement moyen des clients en jours de chiffre d'affaires pour 2022-23 sans chiffres après la virgule, sachant que le taux de TVA qui s'applique est de 20 % fois la proportion des ventes France sur les ventes totales (puisque la TVA ne s'applique pas à l'export).",
    answer_type: "numerical",
    options:     ["jours"]
  },
  {
    position:    15,
    text:        "Calculez le délai de rotation des stocks pour 2023-2024, en jours de coûts des ventes, sans chiffres après la virgule.",
    answer_type: "numerical",
    options:     ["jours"]
  },
  {
    position:    16,
    text:        "Calculez le délai de paiement moyen des fournisseurs au sens large en jours de coûts d'exploitation hors dotation aux amortissements pour 2024-2025, avec un taux de TVA de 20 %, sans chiffres après la virgule.",
    answer_type: "numerical",
    options:     ["jours"]
  },
  {
    position:    17,
    text:        "Calculez, avec un chiffre après la virgule, le ratio des investissements industriels cumulés, nets des cessions cumulées, de 2021-2022 à 2024-2025 sur les dotations aux amortissements cumulées de la même période.",
    answer_type: "numerical",
    options:     ["×"]
  },
  {
    position:    18,
    text:        "Calculez le ratio en pourcents des immobilisations corporelles nettes hors terrain sur les immobilisations corporelles brutes hors terrain pour le premier semestre 2025-2026, sans chiffres après la virgule. (ex : 15,3 % → tapez 15)",
    answer_type: "numerical",
    options:     ["%"]
  },
  {
    position:    19,
    text:        "Calculez le ratio d'endettement bancaire et financier net par rapport à l'excédent brut d'exploitation de Laurent-Perrier pour 2024-2025, avec un chiffre après la virgule.",
    answer_type: "numerical",
    options:     ["×"]
  },
  {
    position:    20,
    text:        "Calculez en 2024-2025 le ratio des actifs courants de Laurent-Perrier sur ses passifs courants avec un chiffre après la virgule. (ex : 1,8 → tapez 1.8)",
    answer_type: "numerical",
    options:     []
  },
  {
    position:    21,
    text:        "Calculez en 2024-2025 le ratio des actifs courants hors stocks de Laurent-Perrier sur ses passifs courants, avec deux chiffres après la virgule. (ex : 1,84 → tapez 1.84)",
    answer_type: "numerical",
    options:     []
  },
  {
    position:    22,
    text:        "Que pensez-vous de vos deux calculs précédents (ratio de liquidité générale et ratio de liquidité réduite) ?",
    answer_type: "multiple",
    options:     [
      "Ils montrent un risque de solvabilité.",
      "Ils montrent un risque de liquidité théorique si les stocks n'avaient pas de valeur.",
      "Le risque de solvabilité est bien théorique car il suffit de vendre une toute petite partie des stocks pour faire face aux dettes à court terme.",
      "Le risque de liquidité est bien théorique car il suffit de vendre une toute petite partie des stocks pour faire face aux dettes à court terme, d'autant qu'il existe un marché secondaire entre maisons de Champagne portant sur des bouteilles encore sans étiquette."
    ]
  },
  {
    position:    23,
    text:        "Les stocks, qui sont comptablement des actifs circulants, ne devraient-ils pas être financés par des dettes bancaires et financières à court terme plutôt que par des dettes bancaires et financières à long terme ?",
    answer_type: "single",
    options:     [
      "Oui, ce serait ainsi respecter l'orthodoxie financière.",
      "Oui, cela permettrait d'avoir un coût de l'endettement bancaire et financier net plus faible car les taux à court terme sont le plus souvent inférieurs aux taux à long terme.",
      "Cela permettrait d'accentuer l'effet de levier et donc d'améliorer la rentabilité des capitaux propres de Laurent-Perrier.",
      "Les stocks sont comptablement des actifs circulants mais, dans ce secteur, ils mettent structurellement plusieurs années avant d'être cédés dans le cycle d'exploitation. Il est donc de bonne orthodoxie financière de les financer par de l'endettement bancaire et financier à plus d'un an, plutôt que par de l'endettement à court terme."
    ]
  },
  {
    position:    24,
    text:        "Laurent-Perrier ne devrait-il pas supprimer le versement d'un dividende en 2023-2024 et en 2024-2025 puisque son flux de trésorerie disponible après charges financières est négatif ces années-là ?",
    answer_type: "multiple",
    options:     [
      "Oui, cela lui permettrait de ne pas accroître son endettement bancaire et financier net.",
      "Non, car sur les 4 années en revue les flux de trésorerie disponible après charges financières ont été très largement positifs et très largement supérieurs aux dividendes versés.",
      "Non, car rapportés aux résultats nets part du groupe, les dividendes versés par Laurent-Perrier sont de l'ordre de 25 %, contre environ 50 % pour la moyenne des sociétés cotées.",
      "Non, car s'agissant d'une entreprise cotée en Bourse, cela serait perçu par les investisseurs comme un mauvais signal sur son avenir."
    ]
  },
  {
    position:    25,
    text:        "Calculez en pourcents avec un chiffre après la virgule la rentabilité économique en 2024-2025 en utilisant comme taux de l'impôt sur les sociétés 2024-2025 le taux apparent calculé en question 11 (IS / résultat avant impôt). Formule : Re = EBIT × (1 − taux IS apparent) / Actif économique. (ex : 15,23 % → tapez 15.2)",
    answer_type: "numerical",
    options:     ["%"]
  },
  {
    position:    26,
    text:        "La dégradation de la rotation de l'actif économique que l'on observe pendant la période sous revue s'explique par :",
    answer_type: "single",
    options:     [
      "la baisse de la marge d'exploitation.",
      "la hausse du point mort d'exploitation.",
      "La hausse des stocks.",
      "La hausse des dividendes versés."
    ]
  },
  {
    position:    27,
    text:        "Calculez le coût annuel apparent en 2024-2025 de la dette bancaire et financière nette de Laurent-Perrier, après impôt sur les sociétés, avec un chiffre après la virgule. Formule : (Charges financières nettes des produits financiers) × (1 − taux IS apparent Q11) / Dette nette. (ex : 15,23 % → tapez 15.2)",
    answer_type: "numerical",
    options:     ["%"]
  },
  {
    position:    28,
    text:        "Le résultat précédent (coût apparent de la dette nette après IS) vous surprend-il ?",
    answer_type: "single",
    options:     [
      "Rien ne me surprend à notre époque.",
      "Non, car cela semble correspondre à la situation du marché actuellement pour une entreprise avec ce niveau d'endettement.",
      "Oui, car cela semble être plus élevé que les conditions du marché actuellement pour une entreprise avec ce niveau d'endettement.",
      "Oui, car cela semble être moins élevé que les conditions du marché actuellement pour une entreprise avec ce niveau d'endettement."
    ]
  },
  {
    position:    29,
    text:        "Qu'allez-vous faire des intérêts minoritaires pour le calcul de la rentabilité des capitaux propres ?",
    answer_type: "single",
    options:     [
      "Rien de particulier et appliquer la formule vue en cours : résultat net hors éléments non récurrents / montant des capitaux propres.",
      "Raisonner avec le résultat net, part du groupe, c'est-à-dire intérêts minoritaires déduits, hors éléments non récurrents / Montant des capitaux propres.",
      "Raisonner avec le résultat net, part du groupe, c'est-à-dire intérêts minoritaires déduits, et hors éléments non récurrents / Montant des capitaux propres part du groupe.",
      "Utiliser une autre méthode."
    ]
  },
  {
    position:    30,
    text:        "Calculez en pourcents avec un chiffre après la virgule la rentabilité des capitaux propres pour 2024-2025, en appliquant la méthode définie en question 29 : résultat net part du groupe (intérêts minoritaires déduits), hors éléments non récurrents, divisé par les capitaux propres part du groupe. (ex : 15,23 % → tapez 15.2)",
    answer_type: "numerical",
    options:     ["%"]
  },
  {
    position:    31,
    text:        "Êtes-vous surpris du résultat de rentabilité des capitaux propres que vous venez de trouver en question 30 ?",
    answer_type: "multiple",
    options:     [
      "Non, car on a bien une rentabilité des capitaux propres supérieure à celle de l'actif économique puisque le coût de la dette nette est inférieur à la rentabilité économique.",
      "Non, c'est une simple manifestation de l'effet de ciseau.",
      "C'est tout à fait normal pour une entreprise qui est au-dessus de son point mort.",
      "C'est une manifestation de l'effet de levier de l'endettement bancaire et financier."
    ]
  }
].freeze

# Supprime les questions dont la position n'est plus dans la liste
positions = QUESTIONS.map { |q| q[:position] }
Question.where.not(position: positions).destroy_all

QUESTIONS.each do |attrs|
  q = Question.find_or_initialize_by(position: attrs[:position])
  q.assign_attributes(attrs)
  q.save!
  puts "  Q#{attrs[:position]}. #{attrs[:text][0..70]}…"
end

puts "\n#{Question.count} question(s) chargée(s)."
