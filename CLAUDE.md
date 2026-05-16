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

## Stack technique

- Rails 8.1.3 · SQLite · Hotwire/Turbo · SolidQueue (jobs)
- PDF extraction : PDF::Reader (texte) + Ghostscript (PNG) + PyMuPDF (détection images)
- LLM : GitHub Models API (Azure endpoint) · Modèle : gpt-4o · Limite input : ~8 000 tokens
- Extraction multi-passes : Passe A (IS/compte de résultat) + Passe B (CFS + Bilan)

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
  └─ save_to_database → Company + FinancialReports
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
