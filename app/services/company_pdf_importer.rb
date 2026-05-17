require "shellwords"

# Service tout-en-un : textifie un PDF page par page (PdfTextifier),
# extrait les données financières via LLM, puis crée tout en base.
#
# Usage :
#   company = CompanyPdfImporter.call(pdf_path: "/tmp/file.pdf")
#
class CompanyPdfImporter
  MODEL = "gpt-4o"

  def self.call(...)
    new(...).call
  end

  def initialize(pdf_path:)
    @pdf_path = pdf_path
  end

  def call
    Rails.logger.info "[CompanyPdfImporter] Textification du PDF..."
    full_text = PdfTextifier.call(@pdf_path)

    Rails.logger.info "[CompanyPdfImporter] Extraction financière (#{full_text.length} chars)..."
    data = parse_with_llm(full_text)

    company = save_to_database(data)
    extract_and_save_questions(full_text, company)
    company
  end

  private

  # ── 1. EXTRACTION ────────────────────────────────────────────────────────

  def parse_with_llm(text)
    call_api(messages: [ { role: "user", content: build_prompt(text) } ])
  end

  # ── 2. APPEL API ─────────────────────────────────────────────────────────

  def call_api(messages:, max_tokens: 8192, normalize: true)
    api_key = ENV["GITHUB_KEY"].presence or raise "GITHUB_KEY absent"

    conn = Faraday.new("https://models.inference.ai.azure.com") do |f|
      f.request  :json
      f.response :json
      f.options.timeout      = 300
      f.options.open_timeout = 10
    end

    response = conn.post("/chat/completions") do |req|
      req.headers["Authorization"] = "Bearer #{api_key}"
      req.headers["Content-Type"]  = "application/json"
      req.body = {
        model:       MODEL,
        messages:    messages,
        temperature: 0,
        max_tokens:  max_tokens
      }.to_json
    end

    unless response.status == 200
      err = response.body.dig("error", "message") || response.body.inspect
      raise "Erreur API (#{response.status}) : #{err}"
    end

    raw      = response.body.dig("choices", 0, "message", "content").to_s
    Rails.logger.info "[CompanyPdfImporter] Réponse LLM (2000 premiers chars) :\n#{raw.first(2000)}"
    json_str = raw[/```json\s*(.*?)\s*```/m, 1] || raw[/\{.*\}/m]
    raise "Aucun JSON trouvé dans la réponse LLM" if json_str.blank?

    parsed = JSON.parse(json_str)
    Rails.logger.info "[CompanyPdfImporter] JSON parsé — years: #{parsed['years']&.length}, company: #{parsed.dig('company', 'name')}"

    if parsed["error"].present?
      raise "Le LLM n'a pas pu extraire les données : #{parsed['error']}"
    end

    normalize ? normalize_json(parsed) : parsed
  rescue JSON::ParserError => e
    raise "JSON invalide : #{e.message}"
  end

  # ── 3. PROMPT ─────────────────────────────────────────────────────────────

  def build_prompt(text)
    <<~PROMPT
      Tu es un expert-comptable et analyste financier.
      Analyse le document financier suivant et extrais TOUTES les informations dans un JSON structuré.

      ## Document
      #{text.truncate(80_000)}

      ## Instructions générales
      - Retourne UNIQUEMENT un bloc JSON valide (aucune explication autour).
      - Utilise `null` pour toute valeur absente ou illisible.
      - Retourne les montants EXACTEMENT tels qu'écrits dans le document, sans les convertir.
      - Si le document indique "En millions d'euros", retourne 305.6 et indique `"unit": 1000000` dans meta.
      - Si le document indique "En milliers d'euros", retourne 305600 et indique `"unit": 1000` dans meta.
      - Si les montants sont déjà en euros, indique `"unit": 1` dans meta.
      - Les montants négatifs sont des nombres négatifs.
      - COLONNES : les tableaux peuvent avoir des colonnes d'exercices ANNUELS (ex: "2022", "2023", "2024") ET des colonnes SEMESTRIELLES ou trimestrielles.
        → N'extrais QUE les colonnes annuelles complètes (12 mois). Ignore les colonnes "S1", "S2", "H1" ou "semestre".
        → Compte bien TOUTES les colonnes annuelles présentes — il peut y avoir 3, 4, ou même 5 exercices dans un seul document.
        → Crée une entrée dans le tableau `years` pour CHAQUE exercice annuel trouvé.
      - Extrais UNIQUEMENT les exercices annuels COMPLETS (12 mois). Ignore les semestres, trimestres ou périodes partielles.
      - Pour les groupes avec exercice décalé (ex: avril-mars), le fiscal_year est l'année de clôture (ex: exercice 2024-2025 → fiscal_year: 2025, period_end_date: "2025-03-31").
      - Pour les P&L au format IFRS "fonction" (coût des ventes, frais commerciaux, frais admin), utilise les champs cost_of_sales, gross_margin, distribution_marketing_costs, administrative_costs. Laisse null les champs PCG s'ils ne sont pas présents.

      ## Structure JSON attendue

      ```json
      {
        "company": {
          "name": "Nom légal de la société",
          "siren": null,
          "sector": "Secteur d'activité détaillé",
          "country": "France",
          "currency": "EUR",
          "accounting_standard": "pcg",
          "is_consolidated": false
        },
        "years": [
          {
            "meta": {
              "fiscal_year": 2023,
              "period_end_date": "2023-12-31",
              "accounting_standard": "pcg",
              "is_consolidated": false,
              "income_format": "nature",
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
            }
          }
        ]
      }
      ```
    PROMPT
  end

  # ── 4. NORMALISATION JSON ─────────────────────────────────────────────────

  def normalize_json(data)
    root_unit = data["unit"]

    years = (data["years"] || []).map do |entry|
      fy_raw = entry.dig("meta", "fiscal_year") || entry["fiscal_year"]
      fy = case fy_raw.to_s
           when /(\d{4})-(\d{4})/ then $2.to_i
           else fy_raw.to_i
           end

      unit = entry.dig("meta", "unit") || root_unit || 1

      meta = (entry["meta"] || {}).merge(
        "fiscal_year"         => fy,
        "unit"                => unit,
        "period_end_date"     => entry.dig("meta", "period_end_date"),
        "accounting_standard" => entry.dig("meta", "accounting_standard") || data.dig("company", "accounting_standard"),
        "is_consolidated"     => entry.dig("meta", "is_consolidated").nil? ? data.dig("company", "is_consolidated") : entry.dig("meta", "is_consolidated"),
        "income_format"       => normalize_income_format(entry.dig("meta", "income_format")) || "fonction"
      )

      is_flat = entry["income_statement"].nil? && (entry["revenue"] || entry["net_income"])

      if is_flat
        entry.merge(
          "meta"                => meta,
          "income_statement"    => extract_flat_income(entry),
          "balance_sheet"       => extract_flat_balance(entry),
          "cash_flow_statement" => extract_flat_cashflow(entry)
        )
      else
        entry.merge("meta" => meta)
      end
    end

    data.merge("years" => years)
  end

  def extract_flat_income(e)
    {
      "revenue"                      => e["revenue"],
      "gross_margin"                 => e["gross_margin"],
      "cost_of_sales"                => e["cost_of_sales"],
      "distribution_marketing_costs" => e["distribution_marketing_costs"] || e["frais_commerciaux"],
      "administrative_costs"         => e["administrative_costs"] || e["frais_administratif"],
      "ebit"                         => e["ebit"] || e["operating_result"],
      "financial_expenses"           => e["financial_expenses"] || e["cout_endettement_net"],
      "financial_income"             => e["financial_income"],
      "income_tax"                   => e["income_tax"] || e["impot"],
      "net_income"                   => e["net_income"] || e["resultat_net"],
      "minority_interests"           => e["minority_interests"] || e["interets_minoritaires"],
      "personnel_expenses"           => e["personnel_expenses"],
      "depreciation_amortization"    => e["depreciation_amortization"] || e["dotations"],
    }
  end

  def extract_flat_balance(e)
    {
      "total_assets"         => e["total_assets"],
      "total_equity"         => e["total_equity"] || e["capitaux_propres"],
      "lt_financial_debt"    => e["lt_financial_debt"],
      "st_financial_debt"    => e["st_financial_debt"],
      "total_inventory"      => e["total_inventory"] || e["stocks"],
      "trade_receivables"    => e["trade_receivables"] || e["clients"],
      "trade_payables"       => e["trade_payables"] || e["fournisseurs"],
      "cash_and_equivalents" => e["cash_and_equivalents"] || e["tresorerie"],
    }
  end

  def extract_flat_cashflow(e)
    {
      "operating_cash_flow" => e["operating_cash_flow"],
      "investing_cash_flow" => e["investing_cash_flow"],
      "free_cash_flow"      => e["free_cash_flow"],
      "capital_expenditure" => e["capital_expenditure"] || e["investissements"],
      "dividends_paid"      => e["dividends_paid"] || e["dividendes"],
    }
  end

  # ── 5. SAUVEGARDE EN BASE ─────────────────────────────────────────────────

  def save_to_database(data)
    company_attrs = data["company"] || {}
    year_entries  = data["years"]   || []

    company_name = company_attrs["name"].to_s.strip
    if company_name.blank?
      raise "Le LLM n'a pas trouvé le nom de la société — vérifier le PDF."
    end

    ActiveRecord::Base.transaction do
      company = Company.find_or_initialize_by(name: company_name)
      company.siren               = company_attrs["siren"]               if company_attrs["siren"].present?
      company.sector              = company_attrs["sector"]              if company_attrs["sector"].present?
      company.country             = company_attrs["country"]             || "France"
      company.currency            = company_attrs["currency"]            || "EUR"
      company.accounting_standard = company_attrs["accounting_standard"] || "pcg"
      company.is_consolidated     = company_attrs["is_consolidated"]     || false
      company.save!

      year_entries.each do |entry|
        meta = entry["meta"] || {}
        unit = (meta["unit"] || 1).to_f

        fiscal_year = meta["fiscal_year"]&.to_i
        next unless fiscal_year

        period_end = meta["period_end_date"] ? Date.parse(meta["period_end_date"]) : Date.new(fiscal_year, 12, 31)

        report = company.financial_reports.find_or_initialize_by(fiscal_year: fiscal_year)
        report.period_end_date     = period_end
        report.accounting_standard = meta["accounting_standard"] || company.accounting_standard
        report.is_consolidated     = meta["is_consolidated"].nil? ? (company.is_consolidated || false) : meta["is_consolidated"]
        report.income_format       = normalize_income_format(meta["income_format"]) || "nature"
        report.source_file         = File.basename(@pdf_path)
        report.save!

        save_sub(report, :income_statement,    entry["income_statement"],    unit)
        save_sub(report, :balance_sheet,       entry["balance_sheet"],       unit)
        save_sub(report, :cash_flow_statement, entry["cash_flow_statement"], unit)
      end

      company
    end
  end

  # ── 6. HELPERS ────────────────────────────────────────────────────────────

  # ── 7. EXTRACTION DES QUESTIONS ──────────────────────────────────────────

  def extract_and_save_questions(full_text, company)
    Rails.logger.info "[CompanyPdfImporter] Extraction des questions..."
    result = call_api(
      messages: [ { role: "user", content: build_questions_prompt(full_text) } ],
      max_tokens: 4096,
      normalize: false
    )

    questions_list = result["questions"] || []
    if questions_list.empty?
      Rails.logger.info "[CompanyPdfImporter] Aucune question trouvée dans le document"
      return
    end

    Rails.logger.info "[CompanyPdfImporter] #{questions_list.size} questions extraites"

    ActiveRecord::Base.transaction do
      questions_list.each do |q|
        position = q["position"].to_i
        next if position == 0 || q["text"].blank?

        question = company.questions.find_or_initialize_by(position: position)
        question.text        = q["text"].to_s.strip
        question.answer_type = normalize_answer_type(q["answer_type"])
        question.options     = Array(q["options"])
        question.save!
      end
    end
  rescue => e
    Rails.logger.warn "[CompanyPdfImporter] Extraction questions échouée : #{e.message}"
  end

  def build_questions_prompt(full_text)
    <<~PROMPT
      Le texte suivant est extrait d'un document d'analyse financière (format ANAFI).
      Extrais TOUTES les questions numérotées et retourne-les en JSON.

      ## Texte du document
      #{full_text.truncate(60_000)}

      ## Instructions
      - Extrais chaque question avec son numéro, son texte complet et ses options de réponse.
      - answer_type :
        "single"    → une seule réponse possible parmi les options
        "multiple"  → plusieurs réponses possibles
        "numerical" → la réponse est un nombre à calculer (pas d'options lettrées)
      - Pour les questions numériques, options = ["unité de la réponse"] (ex: ["millions d'euros"], ["%"], ["jours"])
      - Copier les options exactement telles qu'elles apparaissent dans le document.
      - Si le document ne contient aucune question numérotée, retourner {"questions": []}

      ## Format JSON attendu
      ```json
      {
        "questions": [
          {
            "position": 1,
            "text": "Texte complet de la question telle qu'écrite dans le document",
            "answer_type": "single",
            "options": ["a) option A", "b) option B", "c) option C", "d) option D"]
          },
          {
            "position": 8,
            "text": "Quel est le montant de l'EBE en 2022, en millions d'euros ?",
            "answer_type": "numerical",
            "options": ["millions d'euros"]
          }
        ]
      }
      ```
    PROMPT
  end

  def normalize_answer_type(value)
    case value.to_s.downcase
    when "single", "choix_unique", "unique" then "single"
    when "multiple", "choix_multiple"       then "multiple"
    when "numerical", "numerique", "numérique", "number" then "numerical"
    else "single"
    end
  end

  def normalize_income_format(value)
    return nil if value.nil?
    { "function" => "fonction", "nature" => "nature", "fonction" => "fonction" }.fetch(value.to_s.downcase, value)
  end

  def save_sub(report, association, attrs, unit)
    return unless attrs.is_a?(Hash)

    record = report.public_send(association) || report.public_send(:"build_#{association}")
    record.assign_attributes(scale(attrs, unit))

    if association == :income_statement
      if record.commercial_margin.blank? && record.merchandise_sales && record.merchandise_purchases && record.merchandise_stock_variation
        record.commercial_margin = record.merchandise_sales - record.merchandise_purchases - record.merchandise_stock_variation
      end
      if record.revenue.blank? && record.merchandise_sales
        record.revenue = (record.merchandise_sales || 0) + (record.production_sold || 0)
      end
      if record.ebit.blank? && record.net_income && record.income_tax
        exceptional = (record.exceptional_income || 0) - (record.exceptional_expenses || 0)
        record.ebit = record.net_income + record.income_tax - exceptional - (record.financial_income || 0) + (record.financial_expenses || 0)
      end
      # Point 2 — EBITDA = EBIT + DAP quand non fourni directement
      if record.ebitda.blank? && record.ebit && record.depreciation_amortization
        record.ebitda = record.ebit + record.depreciation_amortization
      end
    end

    if association == :balance_sheet
      # Point 1 — total_assets par reconstruction côté actif quand non fourni
      if record.total_assets.blank?
        fixed       = record.total_fixed_assets_net.to_f
        inventory   = record.total_inventory.to_f
        receivables = record.trade_receivables.to_f
        cash        = record.cash_and_equivalents.to_f
        other       = record.other_operating_receivables.to_f +
                      record.prepaid_expenses.to_f +
                      record.short_term_investments.to_f
        approx = fixed + inventory + receivables + cash + other
        record.total_assets = approx.round(2) if approx > 0
      end
    end

    record.save!
  end

  def scale(attrs, unit)
    attrs.transform_values { |v| v.is_a?(Numeric) ? (v * unit).round(2) : v }
  end
end
