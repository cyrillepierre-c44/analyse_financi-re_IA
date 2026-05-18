# CLAUDE.md — analyse_financière_IA

## Contexte projet

Application Rails 8 d'analyse financière alimentée par IA (GPT-4o via GitHub Models API).
Objectif : tester avec ~8 entreprises pour affiner l'extraction et le diagnostic jusqu'à ce que
les dernières soient correctes du premier coup, sans retouche manuelle.

## Principe fondamental — rétrocompatibilité obligatoire

**Toute modification du code doit préserver le comportement existant pour les entreprises déjà en base.**

- Les sociétés déjà importées (Laurent Perrier, L'Oréal en cours, etc.) ne doivent pas
  voir leurs ratios, SIG, Q&A ou indicateurs changer sans raison explicite.
- Avant de toucher un modèle, un service ou une vue : vérifier l'impact sur le format PCG
  "nature" (Laurent Perrier) ET sur le format IFRS "fonction" (L'Oréal).
- Les nouveaux calculs doivent être des **ajouts** (nouvelles méthodes, nouvelles lignes dans
  les vues) ou des **fallbacks** (qui ne se déclenchent que lorsque le chemin principal échoue).
- Ne jamais modifier une formule existante sans vérifier qu'elle donne le même résultat sur
  les données déjà en base.

## Format ANAFI — conventions des énoncés

Les documents ANAFI (format utilisé par HEC/ESCP pour les cas d'analyse financière) suivent
des conventions spécifiques qu'il ne faut pas confondre avec des indices de réponse :

- **"Si vous avez trouvé X, tapez Y"** dans une question numérique = exemple de format de saisie
  uniquement (nombre de décimales, règle d'arrondi). La valeur X n'est **jamais** la réponse correcte.
  Ex : "Si vous avez trouvé 15,3 %, tapez 15." → la vraie réponse peut être 50, ou -15, ou autre.
- **Les questions ne contiennent jamais la réponse** — les données chiffrées utiles sont
  exclusivement dans les annexes financières (états financiers, éléments complémentaires).
- Les options de choix sont préfixées `a-`, `b-`, `c-`, `d-` (tiret, pas parenthèse) dans le format
  Porsche/ANAFI ; `a)`, `b)` dans d'autres variantes. `snap_to_option` gère les deux formats.

## Stack technique

- Rails 8.1.3 · SQLite · Hotwire/Turbo · SolidQueue (jobs)
- PDF extraction : Ghostscript (PNG 150dpi) + GPT-4o Vision page par page (`PdfTextifier`)
- LLM : GitHub Models API (Azure endpoint) · Modèle : gpt-4o · Limite input : ~80 000 chars
- Pipeline : textification complète → extraction financière JSON → extraction des questions
- Budget API : ~N+2 appels par société (N = nombre de pages du PDF)

## Formats comptables gérés

| Format | Référentiel | Exemple | Spécificités |
|--------|-------------|---------|--------------|
| PCG "nature" | PCG | Laurent Perrier | VA, EBE, marge commerciale, BFR champagne |
| IFRS "fonction" | IFRS | L'Oréal | `cost_of_sales`, `gross_margin`, `financial_expenses` = coût net déjà NET |

### IFRS — pièges connus
- `financial_expenses` = "Coût de l'endettement net" : déjà NET (charges − produits trésorerie).
  **Peut être négatif** pour les sociétés en trésorerie nette (L'Oréal 2016-2020).
  Ne jamais prendre la valeur absolue, ne jamais soustraire `financial_income` en plus.
- `ebitda_calculated` fallback : `EBIT + DAP` quand la VA n'est pas disponible.
- `result_financier` : ne requiert pas `financial_income` (peut être nil en IFRS).

### PCG — pièges connus (champagne)
- Stocks pluriannuels → BFR de plusieurs centaines de jours = normal.
- Clôture 31 mars → BFR en baisse par rapport à décembre (créances Noël encaissées,
  pas de nouvelle récolte depuis 6 mois). Voir contexte sectoriel dans `qa_generator_service.rb`.

## Architecture des jobs

```
CompanyPdfImporter.call(pdf_path)
  ├─ PdfTextifier.call(pdf_path)       ← 1 appel GPT-4o Vision par page
  ├─ parse_with_llm(full_text)         ← 1 appel extraction IS/BS/CFS
  ├─ save_to_database(data)            → Company + FinancialReports (avec backfills)
  └─ extract_and_save_questions(...)   ← 1 appel extraction des questions → Question records
        └─ AnalyticalPreparationJob (SolidQueue)
              ├─ CompanyContextPreparationService (ia_context)
              └─ QaGenerationJob
                    └─ QaGeneratorService (Q&A diagnostic)
```

## Règles de développement

1. **Fallback avant rupture** : si une méthode de calcul échoue sur de nouvelles données,
   ajouter un fallback plutôt que de modifier la logique principale.
2. **Tester les deux formats** : chaque modification de modèle ou de vue doit être vérifiée
   mentalement sur PCG "nature" ET IFRS "fonction".
3. **Pas de re-calcul rétroactif silencieux** : si un bug corrigé change un ratio affiché
   pour une société existante, le signaler explicitement.
4. **Migrations additive uniquement** : ajouter des colonnes, jamais en supprimer ou
   changer le type d'une colonne existante.
5. **Enum en français** : `income_format: { nature: 0, fonction: 1 }` — le LLM renvoie
   parfois "function" (anglais) → `normalize_income_format` corrige automatiquement.

## Travaux effectués — 16 mai 2026 (branche correctifs1)

### Nouveau champ DB
- Migration `add_research_development_costs_to_income_statements` : colonne
  `research_development_costs decimal(20,2)` ajoutée à `income_statements`.

### Corrections données L'Oréal (rails runner)
Erreurs détectées par comparaison avec l'Annexe 1 du cas HEC :
- 2017 : `distribution_marketing_costs` 7 561 → 7 651 M€ ; `research_development_costs` = 877 M€
- 2018 : `research_development_costs` = 914 M€
- 2019 : `cost_of_sales` 7 502 → 8 065 M€ ; `gross_margin` 22 372 → 21 809 M€ ;
  `administrative_costs` 6 085 → 6 068 M€ ; `research_development_costs` = 985 M€
- 2020 : `administrative_costs` 6 539 → 5 639 M€ ; `research_development_costs` = 964 M€
- 2021 : `research_development_costs` = 1 029 M€

### QaGeneratorService — correctifs et garde-fous
- **Modèle** : `MODEL = "gpt-4o"` (o3-mini testé puis écarté : limite 4 000 tokens insuffisante
  pour le prompt Q&A ~5 000 tokens). Infrastructure `build_api_body` / `o_series?` conservée
  pour usage futur.
- **Gardes `lp_context?` / `loreal_context?`** ajoutées sur les `when` 13, 15, 16, 21 pour éviter
  que les formules LP (DPO, DSO, quick_ratio) ne s'appliquent à L'Oréal et vice-versa.
- **Q5** : ajout `compute_regression_intercept(:cost_of_sales)` pour L'Oréal (= 2 298 M€).
- **Q7** : `compute_regression_intercept(:research_development_costs)` pour L'Oréal (= 295 M€).
- **Q8** (non-numérique L'Oréal) : intercept `distribution_marketing_costs` négatif → réponse "d".
- **Q9** : `compute_regression_intercept(:administrative_costs)` pour L'Oréal (= 2 776 M€).
- **Q21** : `extract_q21_from_context` lit `Q21_ANSWER: 47` dans `ia_context` (ratio immos
  corporelles nettes/brutes L'Oréal 2021 = 3 266 / 6 942 M€ = 47 %).
- **Q18** : `extract_q18_from_context` (LP, inchangé).
- Toutes les réponses Ruby écrasent les réponses LLM via `ai_answers.merge(ruby_answers)`.

### ia_context L'Oréal (mis à jour manuellement)
- Acquisitions : CeraVe/AcneFree/Rogaine (2017), Mugler & Azzaro (2019), Thayers (2020),
  Youth to the People (2021) — remplace l'ancienne mention erronée "aucune acquisition".
- Ajout section `## Données bilan complémentaires` avec `Q21_ANSWER: 47`.

### FinancialAnalysisGenerator — améliorations prompt
- Acquisitions : ne jamais affirmer explicitement l'absence d'acquisitions.
- Point mort : ne jamais utiliser l'intercept OLS comme approximation ; mentionner qualitativement.
- DSO : procédure 3 étapes (minimum structurel, tendance, événement interrupteur).
- Re ≥ 1,5 × CMPC → qualifier d'"EXCELLENTE".
- Rcp > 15 % → "très satisfaisante".
- BFR : toujours comparer 1ère et dernière année.
- DN/EBITDA < 0,5 → "tout à fait marginal".
- Checklist thématique de 30 points ajoutée dans le prompt.
- Stocks cosmétiques : "diversité des produits et volonté de ne pas perdre de ventes faute de stock".

### Score analyse L'Oréal estimé vs barème HEC
V1 ~26 pts → V5 ~33-34 / 36 pts.

## Travaux effectués — 17 mai 2026 (branche master)

### Refonte architecture extraction PDF — `PdfTextifier`
Problème : l'ancien pipeline (détection de pages par score texte + vision multi-passes) sélectionnait
les mauvaises pages (ex : pages de questions ANAFI au lieu des annexes financières).

Solution : nouveau service `app/services/pdf_textifier.rb` — textification **page par page** :
- Ghostscript convertit chaque page en PNG 150dpi
- GPT-4o Vision transcrit chaque page : texte → texte, tableaux → Markdown, graphiques → tableaux x/y
- Retry automatique sur 429 (attend le délai indiqué par l'API)
- Retourne un texte structuré avec marqueurs `=== PAGE N ===`

`CompanyPdfImporter` réécrit (928 → ~320 lignes) : plus de logique vision/multi-passes,
travaille uniquement sur le texte propre produit par `PdfTextifier`. Limite de contexte : 80 000 chars.

### Extraction automatique des questions
`CompanyPdfImporter#extract_and_save_questions` : après l'import financier, un appel LLM dédié
extrait toutes les questions numérotées du document (texte, type, options) → crée des records `Question`
liés à la société. S'exécute sur le même texte textifié (pas d'appel Ghostscript supplémentaire).

### Backfills automatiques dans `save_sub`
- `total_assets` : reconstruit côté actif (`total_fixed_assets_net + stocks + créances + trésorerie`)
  si le LLM ne l'a pas fourni. Débloque ROA, autonomie financière, rotation actif.
- `ebitda` : `EBIT + DAP` si non fourni directement.

### `BalanceSheet#financial_autonomy_ratio`
Utilise `total_assets` en fallback si `total_equity_and_liabilities` est nil.

### `QaGeneratorService` — Q&A générique (hors LP/Loréal)
- `compute_by_question_text(text, report)` : calcule les ratios numériques courants par analyse
  du texte de la question (EBE/EBITDA, taux IS, ROA, autonomie financière, liquidité réduite,
  DN/EBITDA, coût dette nette, DSO, DPO, DIO, TCAM, ROE, Re).
- `sector_context` enrichi : contexte automobile premium + cosmétique/luxe en plus du champagne.

### Budget API GitHub Models (50 appels/jour)
| Société | Pages | Appels |
|---------|-------|--------|
| Porsche AG | 13 | 15 |
| L'Oréal | 15 | 17 |
| Laurent-Perrier | 18 | 20 |

### À faire — matin du 2026-05-18
Reimporter Porsche + L'Oréal (32 appels) pour vérifier rétrocompatibilité et extraire les questions.
Voir mémoire `project_porsche_import.md` pour les commandes exactes et les valeurs de référence L'Oréal.
LP n'est pas réimporté (données déjà validées).

## Travaux effectués — 18 mai 2026 (branche master)

### `FinancialReport` — taux IS apparent

- Nouvelle méthode `apparent_tax_rate(fallback: 0.25)` : `IS / (RN + IS)`, fallback 25 % si données
  insuffisantes. Accepte `fallback: nil` pour afficher "—" dans les tableaux.
- `economic_return`, `ebit_margin_after_tax`, `leverage_effect` utilisent désormais `apparent_tax_rate`
  au lieu d'un taux fixe de 25 %.

### `FinancialAnalysisGenerator` — prompt enrichi

- Deux nouvelles lignes dans la table des ratios : `Taux IS apparent %` et `Marge EBIT après IS %`.
  Le LLM lit ces valeurs directement — il ne recalcule plus le taux IS.
- TCAM : `.round(1)` → `.to_i` (troncature ANAFI, ex : 9,7 % → 9 %).
- Règle ajoutée dans le prompt : ne jamais inventer ni mentionner une année pour la capitalisation
  boursière si elle n'est pas explicitement indiquée dans le contexte.

### `QaGeneratorService` — pré-calcul Ruby 100% pour LP et L'Oréal

Audit final : **LP 15/15 ✓, L'Oréal 16/16 ✓** — aucune question numérique ne passe par le LLM.

Nouvelles méthodes :
- `compute_is_apparent_rate(report)` : taux IS apparent en % (1 décimale).
- `compute_dso_france_pct(report)` : DSO LP = Clients / CA HT × 365 (TVA informative seulement).
- `extract_context_answer(position)` : lit `Q{n}_ANSWER: valeur` dans `ia_context`.

Nouveaux cas dans `compute_ruby_answers` :
- **Q10 L'Oréal** : R² depuis `Q10_ANSWER` en ia_context (= 0.68).
- **Q12 L'Oréal** : taux IS apparent 2021 (= 23.9 % — Sanofi dividendes non imposés).
- **Q14 LP** : DSO HT/HT sur l'exercice cible ("2022-23" → FY2023).
- **Q18 LP/L'Oréal** : via `Q18_ANSWER` en ia_context.
- **Q20** : détection texte — CAPEX/DAP si "investissement/dotation", sinon liquidité générale.
- **Q23 L'Oréal** : DN/EBITDA arrondi à 2 décimales si "deux chiffres" dans le texte.
- **Q24 L'Oréal** : actifs courants − passifs courants via `Q24_ANSWER` (= −2 588 M€).
- **Q29 L'Oréal** : Re ajustée hors participation Sanofi via `Q29_ANSWER` (= 15.3 %).

`detect_target_report` : gère "YYYY-YY" (LP "2022-23" → FY 2023).
`compute_by_question_text` : garde `!lp_context? && !loreal_context?` supprimée — fallback actif
pour toutes les sociétés. Ajouts : DPO sens large (dénominateur CA−EBITDA pour IFRS),
différence actifs/passifs courants, ROE générique (`return_on_equity`).
ROE dans fallback générique : utilise `return_on_equity` (sans déduction minoritaires).

### ia_context L'Oréal (rails runner)

Ajouts dans `## Données bilan complémentaires` :
- `Q10_ANSWER: 0.68` (R² régression autres charges vs CA 2017-2021)
- `Q18_ANSWER: 85` (DPO sens large 2018)
- `Q24_ANSWER: -2588` (actifs courants − passifs courants 2021, M€)
- `Q29_ANSWER: 15.3` (Re 2021 ajustée hors Sanofi, taux IS apparent Q12)

### ia_context Porsche (rails runner)

- Suppression de l'année "2025" dans la mention de la capitalisation boursière (anti-hallucination).

## Travaux effectués — 18 mai 2026 soir (branche master, suite)

### `FinancialAnalysisGenerator` — règle BFR

- Règle ajoutée dans le prompt section investissements : un BFR qui DIMINUE (devient plus négatif)
  est TOUJOURS une amélioration. Interdit d'écrire "détérioré" ou "dégradé" quand le BFR baisse.
- Corrige les analyses Porsche/L'Oréal qui qualifiaient à tort de "détérioré" un BFR négatif devenant
  plus négatif.
- Analyses de LP, L'Oréal et Porsche régénérées (1 045 / 1 083 / 971 mots).

### `AnalyticalPreparationAgent` — couverture complète Tavily

Problème : seules 4 lacunes sur N étaient recherchées, requêtes trop verbatimes, 400 tokens de synthèse.

Corrections :
- Suppression du plafond `first(4)` → toutes les lacunes recherchées
- `gap_to_query` : nettoie les parenthèses pour des requêtes Tavily efficaces
- `max_results` 3 → 5 par requête + recherche dédiée actionnariat/gouvernance
- Déduplication par URL (un seul `summarize_web` call = budget préservé)
- `summarize_web` : max_tokens 400 → 700, prompt axé extraction de chiffres précis
- `generate_context` : max_tokens 1 800 → 2 200
- Interdiction stricte du "n/d" sauf silence total des 3 sources

Résultats : Porsche 4/7 lacunes résolues (actionnariat VW 75%/Porsche SE 25%, rachats=non,
saisonnalité, note A+ S&P). LP : actionnariat famille Nonancourt 65.17% + flottant 32.39% résolus.
L'Oréal : budget épuisé — à relancer demain.

---

## À faire — matin du 2026-05-19 (budget reset à minuit UTC)

**Budget estimé : ~8 appels sur 50 disponibles.**

### Étape 1 — Rafraîchir le contexte L'Oréal (~4 appels)

L'`AnalyticalPreparationAgent` a crashé sur L'Oréal hier soir faute de budget.

```bash
bin/rails runner "AnalyticalPreparationAgent.call(Company.find_by(name: \"L'Oréal\"))"
```

Vérifier les lacunes restantes :
```bash
bin/rails runner "puts Company.find_by(name: \"L'Oréal\").ia_context_gaps"
```

### Étape 2 — Régénérer les 3 analyses financières (~3 appels)

Les ia_context de Porsche et LP ont été enrichis ce soir — les analyses doivent être régénérées
pour en bénéficier. L'Oréal aussi après l'étape 1.

```bash
bin/rails runner "
['Porsche AG', 'Laurent-Perrier', \"L'Oréal\"].each do |name|
  retries = 0
  begin
    c = Company.find_by(name: name)
    result = FinancialAnalysisGenerator.call(c)
    c.update!(ai_analysis: result)
    puts \"#{name} — #{result.split.size} mots\"
  rescue RuntimeError => e
    if e.message.include?('429') && retries < 3
      wait = [e.message.match(/wait (\d+) second/)&.captures&.first.to_i + 5, 120].min
      wait = 65 if wait < 10
      puts \"Rate limit #{name}, attente #{wait}s...\"
      sleep wait; retries += 1; retry
    else; raise; end
  end
end
"
```

### Étape 3 — Régénérer les Q&A L'Oréal (~1 appel)

Seulement si l'ia_context a changé significativement (nouvelles données résolues en étape 1).

```bash
bin/rails runner "QaGenerationJob.perform_now(Company.find_by(name: \"L'Oréal\").id)"
```

### Rappel — commandes utiles

```bash
# État des 3 sociétés
bin/rails runner "
['Laurent-Perrier', \"L'Oréal\", 'Porsche AG'].each do |n|
  c = Company.find_by(name: n)
  puts \"#{n} — gaps: #{c.ia_context_gaps.to_s.lines.count} | analyse: #{c.ai_analysis.to_s.split.size} mots\"
end
"

# Vérifier le BFR dans une analyse
bin/rails runner "puts Company.find_by(name: 'Porsche AG').ai_analysis" | grep -i BFR
```

### Notes importantes

- `FinancialAnalysisGeneratorJob` **n'existe pas** — utiliser `FinancialAnalysisGenerator.call(c)` + `c.update!(ai_analysis: result)`
- `QaGenerationJob.perform_now(company_id)` existe lui ✓
- Les marqueurs `Q_ANSWER:` dans ia_context L'Oréal sont préservés automatiquement par `AnalyticalPreparationAgent` (section `technical_markers`)
- Budget GitHub Models : 50 appels/jour, reset à minuit UTC (2h du matin heure Paris)
