require "pdf/reader"

# Service principal : lit un PDF financier et remplit la base de données.
#
# Usage :
#   result = FinancialPdfImporter.call(
#     pdf_path:    "docs/centaur_bilan_2023.pdf",
#     company:     Company.find_or_create_by!(name: "Centaur Bike"),
#     fiscal_year: 2023
#   )
#
class FinancialPdfImporter
  MODEL = "gpt-4o"

  def self.call(...)
    new(...).call
  end

  def initialize(pdf_path:, company:, fiscal_year:, income_format: "nature", accounting_standard: "pcg", is_consolidated: false)
    @pdf_path           = pdf_path
    @company            = company
    @fiscal_year        = fiscal_year
    @income_format      = income_format
    @accounting_standard = accounting_standard
    @is_consolidated    = is_consolidated
  end

  def call
    text = extract_text
    raise "PDF vide ou illisible : #{@pdf_path}" if text.blank?

    data = parse_with_llm(text)
    save_to_database(data)
  end

  private

  # ── 1. EXTRACTION TEXTE ────────────────────────────────────────────────

  def extract_text
    reader = PDF::Reader.new(@pdf_path)
    reader.pages.map(&:text).join("\n")
  rescue => e
    raise "Erreur lecture PDF : #{e.message}"
  end

  # ── 2. ANALYSE LLM ────────────────────────────────────────────────────
  # Appel direct à l'API GitHub Models via Faraday (ruby_llm ajoute /v1/
  # qui n'est pas supporté par models.inference.ai.azure.com)

  def parse_with_llm(text)
    prompt   = build_prompt(text)
    api_key  = ENV["GITHUB_KEY"].presence or raise "GITHUB_KEY absent — vérifiez le fichier .env"

    conn = Faraday.new("https://models.inference.ai.azure.com") do |f|
      f.request  :json
      f.response :json
      f.options.timeout      = 120
      f.options.open_timeout = 10
    end

    response = conn.post("/chat/completions") do |req|
      req.headers["Authorization"] = "Bearer #{api_key}"
      req.headers["Content-Type"]  = "application/json"
      req.body = {
        model:       MODEL,
        messages:    [ { role: "user", content: prompt } ],
        temperature: 0,
        max_tokens:  8192
      }.to_json
    end

    unless response.status == 200
      err = response.body.dig("error", "message") || response.body.inspect
      raise "Erreur API GitHub Models (#{response.status}) : #{err}"
    end

    raw      = response.body.dig("choices", 0, "message", "content").to_s
    json_str = raw[/```json\s*(.*?)\s*```/m, 1] || raw[/\{.*\}/m]
    raise "Aucun JSON trouvé dans la réponse LLM" if json_str.blank?

    parsed = JSON.parse(json_str)
    units = parsed["years"]&.map { |y| y.dig("meta", "unit") } || [ parsed.dig("meta", "unit") ]
    Rails.logger.info "[FinancialPdfImporter] #{File.basename(@pdf_path)} — units détectés: #{units.inspect}"
    Rails.logger.debug "[FinancialPdfImporter] JSON brut LLM:\n#{JSON.pretty_generate(parsed)}"
    parsed
  rescue JSON::ParserError => e
    raise "JSON invalide renvoyé par le LLM : #{e.message}\n#{json_str}"
  end

  def build_prompt(text)
    <<~PROMPT
      Tu es un expert-comptable et analyste financier.
      Analyse le document financier suivant et extrais les données dans un JSON structuré.

      ## Document
      #{text.truncate(24_000)}

      ## Instructions
      - Extrais UNIQUEMENT les exercices annuels COMPLETS (12 mois). Ignore les semestres ou périodes partielles.
      - Retourne UNIQUEMENT un bloc JSON valide (pas d'explication).
      - La clé racine est `"years"` : un tableau avec un objet par exercice fiscal détecté.
      - Utilise `null` pour toute valeur absente ou illisible.
      - NOTATION FRANÇAISE : dans les documents comptables français, l'espace est le séparateur de milliers et la virgule est le séparateur décimal. Exemples : "108 713,31" = 108713.31 ; "25 000" = 25000 ; "7 630,27" = 7630.27. Tu DOIS reconstituer le nombre complet, jamais t'arrêter à l'espace. Retourne toujours un nombre JSON valide (point comme décimal, sans espace ni virgule de milliers) : 108713.31, pas 108 ni 108713.
      - Retourne les montants tels qu'ils apparaissent dans le document (en reconstituant les nombres complets selon la notation française), sans conversion d'unité.
      - Si le document indique "En millions d'euros" et montre "305,6", retourne 305.6 et indique `"unit": 1000000` dans meta.
      - Si le document indique "En milliers d'euros" et montre "305 600", retourne 305600 et indique `"unit": 1000` dans meta.
      - Si les montants sont en euros (mention "Euros", "€" ou pas d'indication d'unité), indique `"unit": 1` dans meta.
      - IMPORTANT : `unit` représente le multiplicateur pour obtenir des euros. Document en k€ → `unit: 1000`. Document en euros → `unit: 1`.
      - Les montants négatifs doivent être des nombres négatifs.
      - Pour les exercices décalés (ex: avril-mars), fiscal_year = année de clôture (ex: 2024-2025 → fiscal_year: 2025, period_end_date: "2025-03-31").
      - Pour `income_format` : "nature" (PCG, avec marge commerciale/VA) ou "fonction" (IFRS, avec coût des ventes/marge brute).
      - Pour les P&L IFRS "fonction", utilise cost_of_sales, gross_margin, distribution_marketing_costs, administrative_costs.
      - `dividends_paid` dans `cash_flow_statement` : cherche dans le tableau de flux ET dans la proposition d'affectation du résultat / tableau de variation des capitaux propres / notes aux comptes. C'est le montant effectivement distribué aux actionnaires au titre de l'exercice précédent.
      - `cash_flow_statement` : même si le document ne présente pas de tableau de flux formalisé, remplis au minimum `net_income`, `depreciation_amortization` et `dividends_paid` depuis les autres sections du document. Ne retourne jamais `null` pour l'objet entier.

      ## Structure JSON attendue
      ```json
      {
        "years": [
          {
            "meta": {
              "document_type": "mixte",
              "income_format": "nature",
              "fiscal_year": 2023,
              "period_end_date": "2023-12-31",
              "accounting_standard": "pcg",
              "is_consolidated": false,
              "currency": "EUR",
              "unit": 1
            },
            "income_statement": {
              "revenue": null,
          "cost_of_sales": null,
          "gross_margin": null,
          "distribution_marketing_costs": null,
          "administrative_costs": null,
          "ebit": null,
          "financial_income": null,
          "financial_expenses": null,
          "current_result": null,
          "exceptional_income": null,
          "exceptional_expenses": null,
          "income_tax": null,
          "net_income": null,
          "dividends_paid": null,
          "retained_earnings": null,
          "minority_interests": null,
          "merchandise_sales": null,
          "merchandise_purchases": null,
          "merchandise_stock_variation": null,
          "commercial_margin": null,
          "production_sold": null,
          "production_stored": null,
          "capitalized_production": null,
          "operating_subsidies": null,
          "raw_materials_purchases": null,
          "raw_materials_stock_variation": null,
          "other_external_expenses": null,
          "taxes_and_duties": null,
          "personnel_expenses": null,
          "depreciation_amortization": null,
          "asset_impairment": null,
          "provisions_charge": null,
          "other_operating_expenses": null,
          "other_operating_income": null,
          "value_added": null,
          "ebitda": null
        },
        "balance_sheet": {
          "intangible_assets_gross": null,
          "intangible_assets_net": null,
          "tangible_assets_gross": null,
          "tangible_assets_net": null,
          "financial_assets_gross": null,
          "financial_assets_net": null,
          "total_fixed_assets_gross": null,
          "total_fixed_assets_net": null,
          "goodwill": null,
          "equity_method_investments": null,
          "raw_materials_inventory": null,
          "merchandise_inventory": null,
          "wip_inventory": null,
          "finished_goods_inventory": null,
          "total_inventory": null,
          "trade_receivables": null,
          "customer_advances_paid": null,
          "other_operating_receivables": null,
          "prepaid_expenses": null,
          "discounted_bills_not_due": null,
          "short_term_investments": null,
          "cash_and_equivalents": null,
          "total_current_assets": null,
          "total_assets": null,
          "share_capital": null,
          "share_premium": null,
          "reserves": null,
          "retained_earnings_bf": null,
          "net_income_period": null,
          "total_equity": null,
          "minority_interests": null,
          "provisions_for_risks": null,
          "lt_financial_debt": null,
          "st_financial_debt": null,
          "finance_lease_debt": null,
          "trade_payables": null,
          "customer_advances_received": null,
          "tax_and_social_liabilities": null,
          "other_operating_liabilities": null,
          "deferred_income": null,
          "total_liabilities": null,
          "total_equity_and_liabilities": null
        },
        "cash_flow_statement": {
          "net_income": null,
          "depreciation_amortization": null,
          "asset_impairment": null,
          "provisions_variation": null,
          "gains_losses_on_disposals": null,
          "self_financing_capacity": null,
          "inventory_variation": null,
          "trade_receivables_variation": null,
          "trade_payables_variation": null,
          "other_wcr_variation": null,
          "total_wcr_variation": null,
          "operating_cash_flow": null,
          "asset_disposals": null,
          "capital_expenditure": null,
          "investing_cash_flow": null,
          "free_cash_flow": null,
          "capital_increase": null,
          "dividends_paid": null,
          "net_debt_change": null,
          "net_debt_opening": null,
          "net_debt_closing": null
        },
        "cost_structures": []
          }
        ]
      }
      ```
    PROMPT
  end

  # ── 3. SAUVEGARDE EN BASE ─────────────────────────────────────────────

  # Retourne un tableau de FinancialReport (1 par année détectée)
  def save_to_database(data)
    # Support ancien format (objet unique) ET nouveau format (tableau years)
    year_entries = if data["years"].is_a?(Array)
                    data["years"]
                  else
                    [ data ]   # rétro-compatibilité : un seul exercice
                  end

    reports = []
    ActiveRecord::Base.transaction do
      year_entries.each do |entry|
        meta = entry["meta"] || {}
        unit = (meta["unit"] || 1).to_f

        report = find_or_create_report(meta)
        save_income_statement(report, entry["income_statement"], unit)       if entry["income_statement"]
        save_balance_sheet(report, entry["balance_sheet"], unit)             if entry["balance_sheet"]
        save_cash_flow_statement(report, entry["cash_flow_statement"] || {}, unit)
        save_cost_structures(report, entry["cost_structures"], unit)         if entry["cost_structures"]&.any?
        reports << report
      end
    end
    reports
  end

  def find_or_create_report(meta)
    fiscal_year   = meta["fiscal_year"]&.to_i || @fiscal_year
    period_end    = meta["period_end_date"] ? Date.parse(meta["period_end_date"]) : Date.new(fiscal_year, 12, 31)
    std           = meta["accounting_standard"] || @accounting_standard
    consolidated  = meta.key?("is_consolidated") ? meta["is_consolidated"] : @is_consolidated
    format        = meta["income_format"] || @income_format

    @company.financial_reports.find_or_initialize_by(fiscal_year: fiscal_year).tap do |r|
      r.period_end_date     = period_end
      r.accounting_standard = std
      r.is_consolidated     = consolidated
      r.income_format       = format
      r.source_file         = File.basename(@pdf_path)
      r.save!
    end
  end

  def save_income_statement(report, attrs, unit)
    record = report.income_statement || report.build_income_statement
    record.assign_attributes(scale(attrs, unit))
    backfill_income_statement(record)
    record.save!
  end

  # Calcule et stocke les champs dérivables si le LLM ne les a pas fournis
  def backfill_income_statement(r)
    # Marge commerciale
    if r.commercial_margin.blank? && r.merchandise_sales && r.merchandise_purchases && r.merchandise_stock_variation
      r.commercial_margin = r.merchandise_sales - r.merchandise_purchases - r.merchandise_stock_variation
    end

    # Revenue = merchandise_sales + production_sold si absent
    if r.revenue.blank? && r.merchandise_sales
      r.revenue = (r.merchandise_sales || 0) + (r.production_sold || 0)
    end

    # EBIT depuis le résultat net si absent (approximation sans exceptionnel)
    if r.ebit.blank? && r.net_income && r.income_tax
      exceptional = (r.exceptional_income || 0) - (r.exceptional_expenses || 0)
      r.ebit = r.net_income + r.income_tax - exceptional - (r.financial_income || 0) + (r.financial_expenses || 0)
    end
  end

  def save_balance_sheet(report, attrs, unit)
    record = report.balance_sheet || report.build_balance_sheet
    record.assign_attributes(scale(attrs, unit))
    record.save!
  end

  def save_cash_flow_statement(report, attrs, unit)
    record = report.cash_flow_statement || report.build_cash_flow_statement
    record.assign_attributes(scale(attrs, unit))
    record.save!
  end

  def save_cost_structures(report, items, unit)
    items.each do |item|
      category = item["cost_category"]
      next unless CostStructure.cost_categories.key?(category)

      cs = report.cost_structures.find_or_initialize_by(cost_category: category)
      cs.fixed_costs    = (item["fixed_costs"].to_f * unit).round(2)    if item["fixed_costs"]
      cs.variable_costs = (item["variable_costs"].to_f * unit).round(2) if item["variable_costs"]
      cs.save!
    end
  end

  # Multiplie tous les montants numériques par le facteur d'unité (ex: 1000 si PDF en k€)
  def scale(attrs, unit)
    return {} unless attrs.is_a?(Hash)
    attrs.transform_values do |v|
      v.is_a?(Numeric) ? (v * unit).round(2) : v
    end
  end
end
