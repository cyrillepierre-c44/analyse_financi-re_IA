require "faraday"

# Génère une analyse financière narrative de qualité professionnelle
# via GPT-4o, à partir des données multi-années d'une société.
#
# Si ANALYSIS_API_URL est défini, délègue au micro-service FastAPI externe.
# Sinon, appelle le LLM directement via GITHUB_KEY.
#
# Usage :
#   text = FinancialAnalysisGenerator.call(company)
#
class FinancialAnalysisGenerator
  MODEL    = "gpt-4o"
  API_BASE = "https://models.inference.ai.azure.com"

  def self.call(company)
    new(company).call
  end

  def initialize(company)
    @company = company
    @reports = company.financial_reports
                      .includes(:income_statement, :balance_sheet, :cash_flow_statement)
                      .order(:fiscal_year)
  end

  def call
    return "Aucune donnée financière disponible pour cette société." if @reports.empty?

    return call_external_api if ENV["ANALYSIS_API_URL"].present?

    api_key = ENV["GITHUB_KEY"].presence or raise "GITHUB_KEY absent — vérifiez le fichier .env"
    prompt  = build_prompt

    conn = Faraday.new(API_BASE) do |f|
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
        temperature: 0.3,
        max_tokens:  2048
      }.to_json
    end

    unless response.status == 200
      err = response.body.dig("error", "message") || response.body.inspect
      raise "Erreur API (#{response.status}) : #{err}"
    end

    response.body.dig("choices", 0, "message", "content").to_s.strip
  end

  # ── Délégation au micro-service externe ──────────────────────────────────

  def call_external_api
    api_url = ENV["ANALYSIS_API_URL"].chomp("/")
    api_key = ENV["ANALYSIS_API_KEY"].presence or raise "ANALYSIS_API_KEY absent"

    conn = Faraday.new(api_url) do |f|
      f.request  :json
      f.response :json
      f.options.timeout      = 180
      f.options.open_timeout = 10
    end

    response = conn.post("/analyze") do |req|
      req.headers["Authorization"] = "Bearer #{api_key}"
      req.headers["Content-Type"]  = "application/json"
      req.body = build_payload.to_json
    end

    unless response.status == 200
      err = response.body.dig("detail") || response.body.inspect
      raise "Erreur micro-service (#{response.status}) : #{err}"
    end

    response.body.dig("analysis").to_s.strip
  end

  def build_payload
    {
      company_name:        @company.name,
      sector:              @company.sector,
      country:             @company.country,
      accounting_standard: @company.accounting_standard,
      cagr_revenue:        @company.cagr_revenue,
      years: @reports.map do |r|
        is = r.income_statement
        bs = r.balance_sheet
        {
          fiscal_year:                    r.fiscal_year,
          revenue:                        is&.revenue,
          commercial_margin:              is&.commercial_margin_calculated,
          commercial_margin_pct:          pct_val(is&.commercial_margin_calculated, is&.revenue),
          value_added:                    is&.value_added_calculated,
          ebitda:                         is&.ebitda_calculated,
          ebitda_margin_pct:              pct_val(is&.ebitda_calculated, is&.revenue),
          ebit:                           is&.ebit,
          ebit_margin_pct:                pct_val(is&.ebit, is&.revenue),
          personnel_expenses:             is&.personnel_expenses,
          depreciation_amortization:      is&.depreciation_amortization,
          net_income:                     is&.net_income,
          net_margin_pct:                 pct_val(is&.net_income, is&.revenue),
          total_assets:                   bs&.total_assets,
          total_fixed_assets_net:         bs&.total_fixed_assets_net,
          total_inventory:                bs&.total_inventory,
          trade_receivables:              bs&.trade_receivables,
          cash_and_equivalents:           bs&.cash_and_equivalents,
          total_equity:                   bs&.total_equity,
          financial_debt:                 (bs&.lt_financial_debt || 0) + (bs&.st_financial_debt || 0),
          working_capital_requirement:    bs&.working_capital_requirement,
          net_financial_debt:             bs&.net_financial_debt,
          economic_return:                r.economic_return,
          return_on_equity:               r.return_on_equity,
          financial_autonomy_ratio:       bs&.financial_autonomy_ratio,
          general_liquidity_ratio:        bs&.general_liquidity_ratio,
          reduced_liquidity_ratio:        bs&.reduced_liquidity_ratio,
          debt_ratio:                     r.debt_ratio,
          interest_coverage_ratio:        r.interest_coverage_ratio,
          days_sales_outstanding:         r.days_sales_outstanding,
          days_inventory_outstanding:     r.days_inventory_outstanding,
          days_payable_outstanding:       r.days_payable_outstanding,
          cash_conversion_cycle:          r.cash_conversion_cycle,
        }
      end
    }
  end

  def pct_val(numerator, denominator)
    return nil unless numerator && denominator&.positive?
    (numerator / denominator * 100).round(2)
  end

  private

  def build_prompt
    lines = []

    lines << "## Société : #{@company.name}"
    lines << "Secteur : #{@company.sector || 'N/R'}  |  Référentiel : #{@company.accounting_standard.upcase}  |  Pays : #{@company.country}"
    lines << ""
    lines << "## Données financières consolidées (en euros)"
    lines << ""

    # Tableau des principaux indicateurs par année
    lines << "### Compte de résultat"
    lines << table_header
    lines << table_row("Chiffre d'affaires",        ->(r){ r.income_statement&.revenue })
    lines << table_row("Marge commerciale",          ->(r){ r.income_statement&.commercial_margin_calculated })
    lines << table_row("Marge commerciale %",        ->(r){ fmt_pct(r.income_statement&.commercial_margin_calculated, r.income_statement&.revenue) })
    lines << table_row("Valeur Ajoutée",             ->(r){ r.income_statement&.value_added_calculated })
    lines << table_row("EBE / EBITDA",               ->(r){ r.income_statement&.ebitda_calculated })
    lines << table_row("Marge EBE %",                ->(r){ fmt_pct(r.income_statement&.ebitda_calculated, r.income_statement&.revenue) })
    lines << table_row("EBIT",                       ->(r){ r.income_statement&.ebit })
    lines << table_row("Marge EBIT %",               ->(r){ fmt_pct(r.income_statement&.ebit, r.income_statement&.revenue) })
    lines << table_row("Charges de personnel",       ->(r){ r.income_statement&.personnel_expenses })
    lines << table_row("Dotations amortissements",   ->(r){ r.income_statement&.depreciation_amortization })
    lines << table_row("Résultat net",               ->(r){ r.income_statement&.net_income })
    lines << table_row("Marge nette %",              ->(r){ fmt_pct(r.income_statement&.net_income, r.income_statement&.revenue) })
    lines << ""

    lines << "### Bilan"
    lines << table_header
    lines << table_row("Total actif",                ->(r){ r.balance_sheet&.total_assets })
    lines << table_row("Actif économique",           ->(r){ r.balance_sheet&.economic_assets })
    lines << table_row("Immobilisations nettes",     ->(r){ r.balance_sheet&.total_fixed_assets_net })
    lines << table_row("Stocks",                     ->(r){ r.balance_sheet&.total_inventory })
    lines << table_row("Créances clients",           ->(r){ r.balance_sheet&.trade_receivables })
    lines << table_row("Trésorerie + VMP",           ->(r){ (r.balance_sheet&.cash_and_equivalents || 0) + (r.balance_sheet&.short_term_investments || 0) })
    lines << table_row("Capitaux propres",           ->(r){ r.balance_sheet&.total_equity })
    lines << table_row("Dettes financières",         ->(r){ (r.balance_sheet&.lt_financial_debt || 0) + (r.balance_sheet&.st_financial_debt || 0) })
    lines << table_row("BFR",                        ->(r){ r.balance_sheet&.working_capital_requirement })
    lines << table_row("Dettes nettes",              ->(r){ r.balance_sheet&.net_financial_debt })
    lines << ""

    lines << "### Ratios clés"
    lines << table_header
    lines << table_row("Re — rentabilité éco. %",   ->(r){ fmt_pct_ratio(r.economic_return) })
    lines << table_row("Rcp — ROE %",               ->(r){ fmt_pct_ratio(r.return_on_equity) })
    lines << table_row("Autonomie financière %",    ->(r){ fmt_pct_ratio(r.balance_sheet&.financial_autonomy_ratio) })
    lines << table_row("Liquidité générale",        ->(r){ r.balance_sheet&.general_liquidity_ratio&.round(2) })
    lines << table_row("Liquidité réduite",         ->(r){ r.balance_sheet&.reduced_liquidity_ratio&.round(2) })
    lines << table_row("Dettes nettes / EBITDA",    ->(r){ r.debt_ratio&.round(2) })
    lines << table_row("Couverture intérêts",       ->(r){ r.interest_coverage_ratio&.round(1) })
    lines << table_row("DSO — délai clients (j)",   ->(r){ r.days_sales_outstanding&.round(0) })
    lines << table_row("DIO — rotation stocks (j)", ->(r){ r.days_inventory_outstanding&.round(0) })
    lines << table_row("DPO — délai fourn. (j)",    ->(r){ r.days_payable_outstanding&.round(0) })
    lines << table_row("CCC — cycle tréso (j)",     ->(r){ r.cash_conversion_cycle&.round(0) })
    lines << ""

    # TCAM
    if (tcam = @company.cagr_revenue)
      lines << "TCAM du chiffre d'affaires (#{@reports.first.fiscal_year}→#{@reports.last.fiscal_year}) : #{(tcam * 100).round(1)} %/an"
      lines << ""
    end

    lines << "---"
    lines << ""
    lines << <<~PROMPT
      ## Mission

      Tu es un analyste financier senior dans un cabinet de conseil en fusions-acquisitions.
      Rédige en français une **analyse financière professionnelle et structurée** de la société #{@company.name}
      à partir des données ci-dessus, telle qu'elle figurerait dans un mémorandum d'information
      destiné à une **banque, des investisseurs en capital, des actionnaires ou des acquéreurs potentiels**.

      ### Structure attendue (utilise ces titres en gras) :

      **1. Activité et dynamique commerciale**
      Analyse l'évolution du CA, de la marge commerciale et de la croissance. Identifie les tendances.

      **2. Rentabilité opérationnelle**
      Commente les marges (EBE, EBIT, nette), la création de valeur ajoutée et les charges structurelles.

      **3. Structure financière et solvabilité**
      Apprécie le niveau des capitaux propres, l'endettement, l'autonomie financière et la couverture des intérêts.

      **4. Liquidité et gestion du BFR**
      Analyse la trésorerie, les ratios de liquidité, le cycle de trésorerie et les rotations.

      **5. Forces, risques et points de vigilance**
      Identifie les 2-3 forces distinctives et les 2-3 risques ou signaux faibles à surveiller.

      **6. Opinion synthétique**
      Donne un avis tranché (favorable / réservé / défavorable) avec une justification concise de 2-3 phrases,
      comme le ferait un comité de crédit ou un comité d'investissement.

      ### Contraintes rédactionnelles :
      - Ton factuel, professionnel et nuancé — pas de superlatifs gratuits
      - Chiffres précis cités à l'appui de chaque affirmation
      - Longueur : 550 à 750 mots
      - Langue : français courant professionnel, pas de jargon inutile
    PROMPT

    lines.join("\n")
  end

  # ── Helpers tableau ───────────────────────────────────────────────────────

  def table_header
    years = @reports.map(&:fiscal_year).join(" | ")
    "| Indicateur | #{years} |"
  end

  def table_row(label, extractor)
    values = @reports.map { |r| extractor.call(r)&.to_s || "—" }.join(" | ")
    "| #{label} | #{values} |"
  end

  def fmt_pct(numerator, denominator)
    return "—" unless numerator && denominator&.positive?
    "#{(numerator / denominator * 100).round(1)} %"
  end

  def fmt_pct_ratio(ratio)
    return "—" unless ratio
    "#{(ratio * 100).round(1)} %"
  end
end
