require "faraday"
require "json"

# Génère les réponses Q&A d'une société via GPT-4o.
# Pour chaque question (choix unique ou multiple), l'IA sélectionne
# la ou les options correctes en se basant sur les données financières.
#
# Usage :
#   QaGeneratorService.call(company)
#
class QaGeneratorService
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
    @questions = company.questions
  end

  def call
    return {} if @reports.empty? || @questions.empty?

    # Étape 1 : l'IA répond à toutes les questions
    raw_json   = ask_llm
    parsed     = JSON.parse(raw_json)
    ai_answers = parsed["answers"] || {}

    # Étape 2 : les réponses numériques calculables en Ruby écrasent l'IA
    ruby_answers = compute_ruby_answers
    all_answers  = ai_answers.merge(ruby_answers.transform_keys(&:to_s))

    # Étape 3 : sauvegarde
    ApplicationRecord.transaction do
      @questions.each do |question|
        selected = Array(all_answers[question.id.to_s]).map(&:to_s)
        next if selected.empty?

        # Pour les questions à choix, caler chaque réponse IA sur l'option la plus proche
        if question.options.any? && !question.numerical?
          selected = selected.filter_map { |s| snap_to_option(s, question.options) }
        end
        next if selected.empty?

        CompanyAnswer.find_or_initialize_by(
          company:  @company,
          question: question
        ).update!(
          selected_options: selected,
          generated_at:     Time.current
        )
      end
    end

    @company.company_answers.includes(:question).order("questions.position")
  end

  # ── Calculs numériques en Ruby ─────────────────────────────────────────────

  def compute_ruby_answers
    results = {}
    first   = @reports.first
    last_r  = @reports.last

    @questions.select(&:numerical?).each do |q|
      value = case q.position
              when 1  then compute_cagr_revenue
              when 8  then lp_context? ? compute_break_even(first) : nil
              when 9  then lp_context? ? compute_margin_of_safety(last_r, compute_break_even(last_r)) : nil
              when 13 then compute_bfr_days(first)
              when 15 then compute_dio_cost_of_sales(@reports.sort_by(&:fiscal_year)[2] || last_r)
              when 16 then compute_dpo_broad(last_r)
              when 17 then compute_capex_to_da_ratio
              when 18 then lp_context? ? extract_q18_from_context : nil
              when 19 then compute_debt_ratio(last_r)
              when 20 then compute_current_ratio(last_r)
              when 21 then compute_quick_ratio(last_r)
              when 25 then compute_economic_return_after_tax(last_r)
              when 27 then compute_net_debt_cost_after_tax(last_r)
              when 30 then compute_roe_group_share(last_r)
              end
      results[q.id] = [ value.to_s ] if value
    end

    results
  end

  def compute_cagr_revenue
    return nil unless @reports.size >= 2
    r0 = @reports.first.income_statement&.revenue
    rn = @reports.last.income_statement&.revenue
    n  = @reports.last.fiscal_year - @reports.first.fiscal_year
    return nil unless r0&.positive? && rn&.positive? && n > 0
    (((rn / r0)**(1.0 / n) - 1) * 100).round(1)
  end

  def compute_break_even(report)
    is = report&.income_statement
    return nil unless is&.gross_margin && is&.ebit && is&.revenue&.positive?
    fixed_costs = is.gross_margin - is.ebit
    taux_mcv    = is.gross_margin / is.revenue
    return nil unless taux_mcv.positive?
    (fixed_costs / taux_mcv / 1_000_000).round(0)
  end

  def compute_margin_of_safety(report, break_even_m)
    return nil unless break_even_m&.positive?
    ca_m = report&.income_statement&.revenue.to_f / 1_000_000
    return nil unless ca_m.positive?
    ((ca_m - break_even_m) / break_even_m * 100).round(0)
  end

  def compute_bfr_days(report)
    bs = report&.balance_sheet
    is = report&.income_statement
    return nil unless bs&.working_capital_requirement && is&.revenue&.positive?
    (bs.working_capital_requirement / is.revenue * 365).round(0)
  end

  def compute_dio_cost_of_sales(report)
    bs = report&.balance_sheet
    is = report&.income_statement
    return nil unless bs&.total_inventory && is&.cost_of_sales&.positive?
    (bs.total_inventory / is.cost_of_sales * 365).round(0)
  end

  # Q16 — DPO fournisseurs "au sens large" = (trade_payables + other_op_liabilities) / (CA - EBITDA) TTC × 365
  def compute_dpo_broad(report, vat_rate: 0.20)
    bs = report&.balance_sheet
    is = report&.income_statement
    return nil unless bs && is
    suppliers = bs.trade_payables.to_f + bs.other_operating_liabilities.to_f
    ebitda    = is.ebitda_calculated
    revenue   = is.revenue
    return nil unless ebitda && revenue&.positive?
    costs_excl_da = revenue - ebitda
    return nil unless costs_excl_da.positive?
    (suppliers / (costs_excl_da * (1 + vat_rate)) * 365).round(0)
  end

  # Q17 — Investissements industriels nets cumulés / DAP cumulées (toutes années)
  def compute_capex_to_da_ratio
    total_net_capex = 0.0
    total_da        = 0.0
    @reports.each do |r|
      cf = r.cash_flow_statement
      is = r.income_statement
      next unless cf && is
      capex     = cf.capital_expenditure.to_f
      disposals = cf.asset_disposals.to_f
      da        = is.depreciation_amortization.to_f
      total_net_capex += capex - disposals
      total_da        += da
    end
    return nil unless total_da.positive?
    (total_net_capex / total_da).round(1)
  end

  # Q18 — Ratio immo corpo nettes/brutes hors terrain (données H1, hors comptes annuels)
  # Convention : ajouter une ligne "Q18_ANSWER: 40" dans l'ia_context de la société.
  def extract_q18_from_context
    ctx = @company.ia_context.to_s
    m = ctx.match(/Q18_ANSWER\s*:\s*(\d+(?:[.,]\d+)?)/i)
    return nil unless m
    val = m[1].tr(",", ".").to_f
    val == val.to_i ? val.to_i : val.round(0)
  end

  def compute_debt_ratio(report)
    return nil unless report.debt_ratio
    report.debt_ratio.round(1)
  end

  def compute_current_ratio(report)
    bs = report&.balance_sheet
    return nil unless bs
    # Actif courant = stocks + créances clients + autres actifs courants + trésorerie
    ca = bs.total_current_assets ||
         (bs.total_inventory.to_f +
          bs.trade_receivables.to_f +
          bs.other_operating_receivables.to_f +
          bs.prepaid_expenses.to_f +
          bs.cash_and_equivalents.to_f +
          bs.short_term_investments.to_f)
    # Passif courant = dettes fournisseurs + autres dettes exploitation + dettes financières CT
    cl = bs.trade_payables.to_f +
         bs.other_operating_liabilities.to_f +
         bs.st_financial_debt.to_f
    return nil unless ca.positive? && cl.positive?
    (ca / cl).round(1)
  end

  def compute_quick_ratio(report)
    bs = report&.balance_sheet
    return nil unless bs
    ca = bs.total_current_assets ||
         (bs.total_inventory.to_f +
          bs.trade_receivables.to_f +
          bs.other_operating_receivables.to_f +
          bs.prepaid_expenses.to_f +
          bs.cash_and_equivalents.to_f +
          bs.short_term_investments.to_f)
    return nil unless bs.total_inventory
    liquid = ca - bs.total_inventory
    cl     = bs.trade_payables.to_f +
             bs.other_operating_liabilities.to_f +
             bs.st_financial_debt.to_f
    return nil unless cl.positive?
    (liquid / cl).round(2)
  end

  def compute_economic_return_after_tax(report)
    is = report&.income_statement
    bs = report&.balance_sheet
    return nil unless is&.ebit && is&.income_tax && bs
    result_avant_is = is.current_result || safe_sum(is.net_income, is.income_tax)
    return nil unless result_avant_is&.positive?
    taux_is  = is.income_tax / result_avant_is
    nopat    = is.ebit * (1 - taux_is)
    ae       = bs.economic_assets
    return nil unless ae&.positive?
    (nopat / ae * 100).round(1)
  end

  def compute_net_debt_cost_after_tax(report)
    is  = report&.income_statement
    bs  = report&.balance_sheet
    return nil unless is&.financial_expenses && bs

    dette_nette = bs.net_financial_debt
    return nil unless dette_nette&.positive?

    # IFRS : financial_expenses = "Coût de l'endettement net" (déjà net trésorerie déduite)
    #         → valeur directement comparable à la dette nette, peut être négative (trésorerie nette)
    # PCG  : financial_expenses = charges brutes → on soustrait les produits financiers
    charges_nettes = if report.ifrs?
                       is.financial_expenses
                     else
                       is.financial_expenses.to_f - is.financial_income.to_f
                     end
    return nil unless charges_nettes&.positive?

    result_avant_is = is.current_result || safe_sum(is.net_income, is.income_tax)
    return nil unless result_avant_is&.positive? && is.income_tax
    taux_is = is.income_tax / result_avant_is

    (charges_nettes / dette_nette * (1 - taux_is) * 100).round(1)
  end

  def compute_roe_group_share(report)
    is = report&.income_statement
    bs = report&.balance_sheet
    return nil unless is&.net_income && bs&.total_equity
    rn_group = safe_diff(is.net_income, is.minority_interests) || is.net_income
    cp_group = safe_diff(bs.total_equity, bs.minority_interests) || bs.total_equity
    return nil unless cp_group&.positive?
    (rn_group / cp_group * 100).round(1)
  end

  private

  def ask_llm
    api_key = ENV["GITHUB_KEY"].presence or raise "GITHUB_KEY absent — vérifiez le fichier .env"

    conn = Faraday.new(API_BASE) do |f|
      f.request  :json
      f.response :json
      f.options.timeout      = 120
      f.options.open_timeout = 10
    end

    body = {
      model:           MODEL,
      messages:        [
        { role: "system", content: system_prompt },
        { role: "user",   content: build_prompt }
      ],
      temperature:     0.1,
      max_tokens:      4096,
      response_format: { type: "json_object" }
    }.to_json

    retries = 0
    response = loop do
      r = conn.post("/chat/completions") do |req|
        req.headers["Authorization"] = "Bearer #{api_key}"
        req.headers["Content-Type"]  = "application/json"
        req.body = body
      end

      if r.status == 429 && retries < 3
        wait = r.body.dig("error", "message").to_s.match(/wait (\d+) second/)&.captures&.first.to_i
        wait = [ wait > 0 ? wait + 5 : 65, 120 ].min
        Rails.logger.info "[QaGeneratorService] 429 rate-limit — attente #{wait}s (tentative #{retries + 1}/3)"
        sleep wait
        retries += 1
        next
      end

      break r
    end

    unless response.status == 200
      err = response.body.dig("error", "message") || response.body.inspect
      raise "Erreur API (#{response.status}) : #{err}"
    end

    response.body.dig("choices", 0, "message", "content").to_s.strip
  end

  def system_prompt
    <<~PROMPT
      Tu es un analyste financier expert. Tu réponds UNIQUEMENT en JSON valide.
      Le format de réponse attendu est :
      {
        "answers": {
          "<question_id>": ["<option choisie>"],
          "<question_id>": ["<option 1>", "<option 2>"]
        }
      }
      Pour les questions à réponse unique, le tableau contient exactement 1 élément.
      Pour les questions à réponses multiples, le tableau peut contenir plusieurs éléments.
      Tu dois UNIQUEMENT choisir parmi les options proposées — ne pas inventer d'autres réponses.
      Base tes réponses principalement sur les données financières fournies.
      Pour les questions qui portent sur les caractéristiques qualitatives du secteur d'activité
      (saisonnalité, cycles, structure de marché, pratiques industrielles…), tu peux et tu dois
      compléter l'analyse avec tes connaissances du secteur indiqué, notamment ses spécificités
      opérationnelles que les comptes annuels ne reflètent pas directement.
    PROMPT
  end

  def build_prompt
    lines = []

    lines << "## Données financières — #{@company.name}"
    lines << "Secteur : #{@company.sector || 'N/R'}  |  Référentiel : #{@company.accounting_standard.upcase}  |  Pays : #{@company.country}"
    lines << ""

    # Extraire la proportion de ventes France depuis ia_context (pour DSO avec TVA)
    # Convention : ajouter une ligne "FRANCE_PCT: 19.5" dans l'ia_context de la société.
    if (m = @company.ia_context.to_s.match(/FRANCE_PCT\s*:\s*(\d+(?:[.,]\d+)?)/i))
      pct_france = m[1].tr(",", ".").to_f
      lines << "**Proportion ventes France : #{pct_france} % — à utiliser pour le calcul du DSO avec ajustement TVA (taux TVA effectif = 20 % × #{pct_france} % = #{(0.20 * pct_france).round(2)} %).**"
      lines << ""
    end

    # Résultats pré-calculés en Ruby — à utiliser comme référence pour les questions dépendantes
    precomputed = compute_ruby_answers
    q_map = @questions.index_by(&:id)
    if precomputed.any?
      lines << "### Résultats pré-calculés (valeurs exactes à utiliser comme référence)"
      precomputed.sort_by { |qid, _| q_map[qid]&.position.to_i }.each do |qid, val|
        q = q_map[qid]
        next unless q
        unit = q.options.first || ""
        lines << "- Q#{q.position} — #{q.text.truncate(80)} → **#{val.first} #{unit}**"
      end
      lines << ""
    end

    lines << "## Contexte sectoriel — éléments clés pour l'analyse"
    lines << ""
    lines << sector_context
    lines << ""
    lines << "## Données financières brutes"
    lines << ""

    lines << "### Compte de résultat"
    lines << table_header
    lines << table_row("Chiffre d'affaires",         ->(r){ r.income_statement&.revenue })
    lines << table_row("Coût des ventes",            ->(r){ r.income_statement&.cost_of_sales })
    lines << table_row("Marge brute",                ->(r){ r.income_statement&.gross_margin || safe_diff(r.income_statement&.revenue, r.income_statement&.cost_of_sales) })
    lines << table_row("Marge brute %",              ->(r){ fmt_pct(r.income_statement&.gross_margin || safe_diff(r.income_statement&.revenue, r.income_statement&.cost_of_sales), r.income_statement&.revenue) })
    lines << table_row("EBITDA",                     ->(r){ r.income_statement&.ebitda_calculated })
    lines << table_row("Marge EBITDA %",             ->(r){ fmt_pct(r.income_statement&.ebitda_calculated, r.income_statement&.revenue) })
    lines << table_row("EBIT",                       ->(r){ r.income_statement&.ebit })
    lines << table_row("Marge EBIT %",               ->(r){ fmt_pct(r.income_statement&.ebit, r.income_statement&.revenue) })
    lines << table_row("Charges personnel",          ->(r){ r.income_statement&.personnel_expenses })
    lines << table_row("Dotations amortissements",   ->(r){ r.income_statement&.depreciation_amortization })
    lines << table_row("Charges financières",        ->(r){ r.income_statement&.financial_expenses })
    lines << table_row("Produits financiers",        ->(r){ r.income_statement&.financial_income })
    lines << table_row("Résultat avant IS",          ->(r){ r.income_statement&.current_result || safe_sum(r.income_statement&.net_income, r.income_statement&.income_tax) })
    lines << table_row("Impôt sur les sociétés",     ->(r){ r.income_statement&.income_tax })
    lines << table_row("Résultat net",               ->(r){ r.income_statement&.net_income })
    lines << table_row("dont intérêts minoritaires", ->(r){ r.income_statement&.minority_interests })
    lines << table_row("Résultat net part du groupe",->(r){ safe_diff(r.income_statement&.net_income, r.income_statement&.minority_interests) })
    lines << table_row("Marge nette %",              ->(r){ fmt_pct(r.income_statement&.net_income, r.income_statement&.revenue) })
    lines << ""

    lines << "### Bilan"
    lines << table_header
    lines << table_row("Total actif",                ->(r){ r.balance_sheet&.total_assets })
    lines << table_row("Immo. corpo. brutes",        ->(r){ r.balance_sheet&.tangible_assets_gross })
    lines << table_row("Immo. corpo. nettes",        ->(r){ r.balance_sheet&.tangible_assets_net })
    lines << table_row("Total immo. nettes",         ->(r){ r.balance_sheet&.total_fixed_assets_net })
    lines << table_row("Stocks",                     ->(r){ r.balance_sheet&.total_inventory })
    lines << table_row("Créances clients",           ->(r){ r.balance_sheet&.trade_receivables })
    lines << table_row("Trésorerie",                 ->(r){ r.balance_sheet&.cash_and_equivalents })
    lines << table_row("Actif courant (approx.)",    ->(r){ safe_diff(r.balance_sheet&.total_assets, r.balance_sheet&.total_fixed_assets_net) })
    lines << table_row("Capitaux propres (total)",   ->(r){ r.balance_sheet&.total_equity })
    lines << table_row("dont intérêts minoritaires", ->(r){ r.balance_sheet&.minority_interests })
    lines << table_row("CP part du groupe",          ->(r){ safe_diff(r.balance_sheet&.total_equity, r.balance_sheet&.minority_interests) })
    lines << table_row("Dettes financières LT",      ->(r){ r.balance_sheet&.lt_financial_debt })
    lines << table_row("Dettes financières CT",      ->(r){ r.balance_sheet&.st_financial_debt })
    lines << table_row("Dettes financières totales", ->(r){ (r.balance_sheet&.lt_financial_debt || 0) + (r.balance_sheet&.st_financial_debt || 0) })
    lines << table_row("Dettes fournisseurs",        ->(r){ r.balance_sheet&.trade_payables })
    lines << table_row("Dettes nettes",              ->(r){ r.balance_sheet&.net_financial_debt })
    lines << table_row("BFR",                        ->(r){ r.balance_sheet&.working_capital_requirement })
    lines << table_row("Passif courant (approx.)",   ->(r){ [r.balance_sheet&.trade_payables.to_f, r.balance_sheet&.other_operating_liabilities.to_f, r.balance_sheet&.st_financial_debt.to_f].then { |a| a.sum > 0 ? a.sum : nil } })
    lines << ""

    lines << "### Flux de trésorerie"
    lines << table_header
    lines << table_row("Investissements (capex)",    ->(r){ r.cash_flow_statement&.capital_expenditure })
    lines << table_row("Cessions d'actifs",          ->(r){ r.cash_flow_statement&.asset_disposals })
    lines << table_row("Dividendes versés",          ->(r){ r.cash_flow_statement&.dividends_paid })
    lines << table_row("CAF / Self-financing",       ->(r){ r.cash_flow_statement&.self_financing_capacity })
    lines << table_row("FCF",                        ->(r){ r.cash_flow_statement&.free_cash_flow })
    lines << ""

    lines << "### Ratios"
    lines << table_header
    lines << table_row("Re — rentab. éco. %",        ->(r){ fmt_pct_ratio(r.economic_return) })
    lines << table_row("ROE %",                      ->(r){ fmt_pct_ratio(r.return_on_equity) })
    lines << table_row("Autonomie fin. %",           ->(r){ fmt_pct_ratio(r.balance_sheet&.financial_autonomy_ratio) })
    lines << table_row("Liquidité générale",         ->(r){ r.balance_sheet&.general_liquidity_ratio&.round(2) })
    lines << table_row("DN / EBITDA",                ->(r){ r.debt_ratio&.round(2) })
    lines << table_row("Couverture intérêts",        ->(r){ r.interest_coverage_ratio&.round(1) })
    lines << table_row("DSO (jours)",                ->(r){ r.days_sales_outstanding&.round(0) })
    lines << table_row("DIO (jours)",                ->(r){ r.days_inventory_outstanding&.round(0) })
    lines << table_row("DPO (jours)",                ->(r){ r.days_payable_outstanding&.round(0) })
    lines << ""

    if (tcam = @company.cagr_revenue)
      first_label = @company.fiscal_year_label(@reports.first.fiscal_year)
      last_label  = @company.fiscal_year_label(@reports.last.fiscal_year)
      lines << "TCAM CA (#{first_label}→#{last_label}) : #{(tcam * 100).round(1)} %/an"
      lines << ""
    end

    lines << "---"
    lines << ""
    lines << "## Questions auxquelles tu dois répondre"
    lines << ""

    @questions.each do |q|
      type_label = if q.numerical?
                     "valeur numérique — retourne uniquement le nombre (respecte la précision indiquée dans la question, sinon arrondi à 1 décimale), sans unité ni symbole"
                   elsif q.multiple?
                     "réponses multiples possibles — choisis une ou plusieurs options"
                   else
                     "réponse unique — choisis exactement 1 option"
                   end
      lines << "Question ID #{q.id} (#{type_label}) : #{q.text}"
      lines << "Options : #{q.options.join(' | ')}" if q.options.any?
      lines << ""
    end

    lines.join("\n")
  end

  def table_header
    years = @reports.map { |r| @company.fiscal_year_label(r.fiscal_year) }.join(" | ")
    "| Indicateur | #{years} |"
  end

  def table_row(label, extractor)
    values = @reports.map { |r| fmt_m(extractor.call(r)) }.join(" | ")
    "| #{label} | #{values} |"
  end

  def fmt_m(value)
    return "—" if value.nil?
    return value.to_s if value.is_a?(String)  # déjà formaté (%, ratio, etc.)
    m = value.to_f / 1_000_000
    "#{m.round(1)} M€"
  end

  def fmt_pct(numerator, denominator)
    return "—" unless numerator && denominator&.positive?
    "#{(numerator / denominator * 100).round(1)} %"
  end

  def fmt_pct_ratio(ratio)
    return "—" unless ratio
    "#{(ratio * 100).round(1)} %"
  end

  def sector_context
    # Priorité au contexte saisi manuellement sur la fiche société
    return @company.ia_context.to_s.strip if @company.ia_context.present?

    # Fallback : contexte champagne auto-détecté
    sector = @company.sector.to_s.downcase
    if sector.include?("champagne") || sector.include?("vin") || sector.include?("spiritueux")
      <<~TEXT
        Spécificités du secteur Champagne à prendre en compte pour répondre aux questions :
        - **Saisonnalité des ventes** : les expéditions sont concentrées sur le 4e trimestre (octobre–décembre), avec un pic marqué pour Noël et le Nouvel An. Les ventes au 31 mars reflètent donc un creux post-fêtes.
        - **Saisonnalité des achats** : les achats de raisin ont lieu une seule fois par an, lors des **vendanges** (septembre–octobre). Ce sont donc des achats fortement saisonniers, concentrés sur quelques semaines. Les fournisseurs (vignerons) sont payés peu après la récolte.
        - **Stocks pluriannuels** : la réglementation impose un élevage minimum de 15 mois pour un champagne non-millésimé (36 mois pour les millésimés). Les stocks représentent donc plusieurs années de chiffre d'affaires — un BFR de plusieurs centaines de jours est normal dans ce secteur.
        - **Saisonnalité du BFR par date de clôture** :
          - **30 septembre** : BFR au pic annuel — la nouvelle récolte vient d'entrer en stock (achats de raisin de l'année), les stocks de produits finis sont encore importants avant les fêtes, et les créances clients sont modestes (ventes estivales).
          - **31 décembre** : BFR encore très élevé — ventes de Noël/Nouvel An génèrent de grosses créances clients, et la récolte est toujours en stock pour élevage.
          - **31 mars** (clôture LP) : BFR en baisse par rapport à décembre (les clients Noël/Nouvel An ont payé, réduction des créances) ET en baisse par rapport à septembre (aucune nouvelle récolte depuis 6 mois — la prochaine est en septembre). BFR probablement plus élevé qu'au 30 juin.
          - **30 juin** : BFR au plus bas annuel — les stocks de produits finis ont baissé après Noël (expéditions sans remplacement), pas de nouvelle récolte avant septembre, créances clients faibles (creux des ventes).
        - **Marché secondaire** : il existe un marché secondaire entre maisons de Champagne portant sur des bouteilles en cours d'élevage, sans étiquette, ce qui donne une certaine liquidité aux stocks.
        - **Cyclicité** : le secteur est cyclique (sensible aux crises économiques, à la géopolitique, aux changes). En volume, le marché mondial du Champagne est **stagnant** depuis plusieurs décennies (autour de 300 millions de bouteilles/an) : la croissance du chiffre d'affaires provient principalement de la hausse des prix, pas des volumes.
      TEXT
    else
      ""
    end
  end

  # Cale une réponse IA sur l'option réelle la plus proche (évite les non-matchs par caractère manquant).
  # Retourne nil si aucune option n'est suffisamment proche (évite les faux positifs).
  def snap_to_option(ai_text, options)
    normalized = ai_text.strip.downcase.gsub(/\s+/, " ")

    # 1. Correspondance exacte
    exact = options.find { |o| o.strip.downcase.gsub(/\s+/, " ") == normalized }
    return exact if exact

    # 2. Correspondance par lettre seule : "a" → option commençant par "a)" ou "a."
    if normalized =~ /\A[a-z]\z/
      letter_match = options.find { |o| o.strip.downcase =~ /\A#{Regexp.escape(normalized)}[\.\)]\s/i }
      return letter_match if letter_match
    end

    # 3. Correspondance par inclusion (l'un contient l'autre à 85 %+ de la longueur)
    best = options.max_by do |o|
      opt_norm = o.strip.downcase.gsub(/\s+/, " ")
      shorter, longer = [normalized, opt_norm].sort_by(&:length)
      longer.length > 0 ? shorter.length.to_f / longer.length : 0
    end
    best_norm = best.strip.downcase.gsub(/\s+/, " ")
    shorter, longer = [normalized, best_norm].sort_by(&:length)
    ratio = longer.length > 0 ? shorter.length.to_f / longer.length : 0
    ratio >= 0.85 ? best : nil
  end

  def safe_diff(a, b)
    return nil unless a && b
    a - b
  end

  def safe_sum(a, b)
    return nil unless a && b
    a + b
  end

  # Vrai si les questions contiennent des références à Laurent-Perrier (calculs LP-spécifiques)
  def lp_context?
    @lp_context ||= @questions.any? { |q|
      q.text.match?(/Laurent.?Perrier/i)
    }
  end
end
