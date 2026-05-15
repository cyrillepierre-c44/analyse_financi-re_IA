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
