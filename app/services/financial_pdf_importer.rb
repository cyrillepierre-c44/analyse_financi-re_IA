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

  def parse_with_llm(text)
    prompt = build_prompt(text)
    chat   = RubyLLM.chat(model: MODEL)
    response = chat.ask(prompt)
    raw = response.content.to_s

    # Extraire le bloc JSON de la réponse (entre ```json ... ``` ou directement)
    json_str = raw[/```json\s*(.*?)\s*```/m, 1] || raw[/\{.*\}/m]
    raise "Aucun JSON trouvé dans la réponse LLM" if json_str.blank?

    JSON.parse(json_str)
  rescue JSON::ParserError => e
    raise "JSON invalide renvoyé par le LLM : #{e.message}\n#{json_str}"
  end

  def build_prompt(text)
    <<~PROMPT
      Tu es un expert-comptable et analyste financier.
      Analyse le document financier suivant et extrais les données dans un JSON structuré.

      ## Document
      #{text.truncate(12_000)}

      ## Instructions
      - Retourne UNIQUEMENT un bloc JSON valide (pas d'explication).
      - Utilise `null` pour toute valeur absente ou illisible.
      - Tous les montants sont en euros (entiers ou décimaux, jamais de symbole).
      - Les montants négatifs doivent être des nombres négatifs.
      - Pour `document_type`, identifie parmi : "bilan", "compte_resultat", "tableau_tresorerie", "mixte".
      - Pour `income_format`, identifie : "nature" ou "fonction".
      - Pour `period_end_date`, format ISO : "YYYY-MM-DD".

      ## Structure JSON attendue
      ```json
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
      ```
    PROMPT
  end

  # ── 3. SAUVEGARDE EN BASE ─────────────────────────────────────────────

  def save_to_database(data)
    meta = data["meta"] || {}
    unit = (meta["unit"] || 1).to_f

    ActiveRecord::Base.transaction do
      report = find_or_create_report(meta)

      save_income_statement(report, data["income_statement"], unit)     if data["income_statement"]
      save_balance_sheet(report, data["balance_sheet"], unit)           if data["balance_sheet"]
      save_cash_flow_statement(report, data["cash_flow_statement"], unit) if data["cash_flow_statement"]
      save_cost_structures(report, data["cost_structures"], unit)       if data["cost_structures"]&.any?

      report
    end
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
    record.save!
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
