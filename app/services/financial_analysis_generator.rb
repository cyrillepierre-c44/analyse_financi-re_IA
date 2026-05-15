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
  MODEL            = "gpt-4o"
  API_BASE         = "https://models.inference.ai.azure.com"
  MAX_CONTEXT_CHARS = 4_000  # ia_context tronqué pour rester sous 8k tokens

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

    conn = Faraday.new(API_BASE) do |f|
      f.request  :json
      f.response :json
      f.options.timeout      = 120
      f.options.open_timeout = 10
    end

    messages = [ { role: "user", content: build_prompt } ]
    result   = llm_call(conn, api_key, messages)

    word_count = result.split.size
    if word_count > 1200 || word_count < 900
      messages << { role: "assistant", content: result }
      messages << { role: "user", content: trim_instruction(word_count) }
      result = llm_call(conn, api_key, messages)
    end

    result
  end

  def llm_call(conn, api_key, messages)
    response = conn.post("/chat/completions") do |req|
      req.headers["Authorization"] = "Bearer #{api_key}"
      req.headers["Content-Type"]  = "application/json"
      req.body = {
        model:       MODEL,
        messages:    messages,
        temperature: 0.2,
        max_tokens:  2000
      }.to_json
    end

    unless response.status == 200
      err = response.body.dig("error", "message") || response.body.inspect
      raise "Erreur API (#{response.status}) : #{err}"
    end

    response.body.dig("choices", 0, "message", "content").to_s.strip
  end

  def enforce_word_limit(text, max:)
    return text if text.split.size <= max
    # Trouver la position caractère du mot max dans le texte original (préserve les \n)
    pos = 0
    max.times do
      m = text.match(/\S+/, pos)
      break unless m
      pos = m.end(0)
    end
    # Reculer jusqu'au dernier point/? /! pour ne pas couper en pleine phrase
    excerpt   = text[0...pos]
    last_stop = excerpt.rindex(/[.!?]/)
    last_stop ? text[0..last_stop] : excerpt
  end

  def trim_instruction(word_count)
    if word_count > 1200
      "Ta note fait #{word_count} mots, c'est trop long. Réécris-la en 1 050 mots (900-1 200). " \
      "Garde l'introduction, les 4 sections complètes et tous les chiffres clés. " \
      "1 paragraphe par indicateur, 2 phrases max. Supprime les répétitions."
    else
      "Ta note fait seulement #{word_count} mots. Développe chaque section pour atteindre 1 050 mots (900-1 200). " \
      "Respecte l'introduction + le plan en 4 parties. Ajoute des chiffres ou des précisions analytiques là où c'est pertinent."
    end
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

    # ── En-tête société ────────────────────────────────────────────────────
    lines << "## Société : #{@company.name}"
    lines << "Secteur : #{@company.sector || 'N/R'}  |  Référentiel : #{@company.accounting_standard&.upcase}  |  Pays : #{@company.country}"
    if (tcam = @company.cagr_revenue)
      sign = tcam >= 0 ? "+" : ""
      lines << "TCAM du CA (#{@reports.first.fiscal_year}→#{@reports.last.fiscal_year}) : #{sign}#{(tcam * 100).round(1)} %/an"
    end
    lines << ""

    # ── Contexte sectoriel et guidage analytique ────────────────────────────
    if @company.ia_context.present?
      ctx = @company.ia_context.strip
      ctx = ctx[0, MAX_CONTEXT_CHARS] + "…" if ctx.length > MAX_CONTEXT_CHARS
      lines << "## Contexte et données sectorielles"
      lines << ctx
      lines << ""
    end

    # ── Données financières en M€ ─────────────────────────────────────────
    lines << "## Données financières consolidées (en millions d'euros)"
    lines << ""

    lines << "### Compte de résultat"
    lines << table_header
    lines << table_row("Chiffre d'affaires (M€)",    ->(r){ fmt_m(r.income_statement&.revenue) })
    lines << table_row("Marge brute (M€)",            ->(r){ fmt_m(r.income_statement&.gross_margin || r.income_statement&.commercial_margin_calculated) })
    lines << table_row("Marge brute %",               ->(r){ fmt_pct(r.income_statement&.gross_margin || r.income_statement&.commercial_margin_calculated, r.income_statement&.revenue) })
    lines << table_row("EBITDA (M€)",                 ->(r){ fmt_m(r.income_statement&.ebitda_calculated) })
    lines << table_row("Marge EBITDA %",              ->(r){ fmt_pct(r.income_statement&.ebitda_calculated, r.income_statement&.revenue) })
    lines << table_row("EBIT (M€)",                   ->(r){ fmt_m(r.income_statement&.ebit) })
    lines << table_row("Marge EBIT %",                ->(r){ fmt_pct(r.income_statement&.ebit, r.income_statement&.revenue) })
    lines << table_row("Résultat net (M€)",           ->(r){ fmt_m(r.income_statement&.net_income) })
    lines << table_row("Marge nette %",               ->(r){ fmt_pct(r.income_statement&.net_income, r.income_statement&.revenue) })
    lines << table_row("Dotations amort. (M€)",       ->(r){ fmt_m(r.income_statement&.depreciation_amortization) })
    lines << ""

    lines << "### Bilan"
    lines << table_header
    lines << table_row("Actif économique (M€)",               ->(r){ fmt_m(r.balance_sheet&.economic_assets) })
    lines << table_row("Goodwill (M€)",                       ->(r){ fmt_m(r.balance_sheet&.goodwill) })
    lines << table_row("Immos incorporelles nettes ex GW (M€)", ->(r){ fmt_m(r.balance_sheet&.intangible_assets_net) })
    lines << table_row("Immos corporelles nettes (M€)",       ->(r){ fmt_m(r.balance_sheet&.tangible_assets_net) })
    lines << table_row("Stocks (M€)",                         ->(r){ fmt_m(r.balance_sheet&.total_inventory) })
    lines << table_row("Créances clients (M€)",               ->(r){ fmt_m(r.balance_sheet&.trade_receivables) })
    lines << table_row("Trésorerie (M€)",                     ->(r){ fmt_m((r.balance_sheet&.cash_and_equivalents || 0) + (r.balance_sheet&.short_term_investments || 0)) })
    lines << table_row("Capitaux propres (M€)",               ->(r){ fmt_m(r.balance_sheet&.total_equity) })
    lines << table_row("Dettes financières (M€)",             ->(r){ fmt_m((r.balance_sheet&.lt_financial_debt || 0) + (r.balance_sheet&.st_financial_debt || 0)) })
    lines << table_row("Dette nette (M€)",                    ->(r){ fmt_m(r.balance_sheet&.net_financial_debt) })
    lines << table_row("BFR (M€)",                            ->(r){ fmt_m(r.balance_sheet&.working_capital_requirement) })
    lines << ""

    lines << "### Ratios clés"
    lines << table_header
    lines << table_row("Re — rentabilité éco. %",    ->(r){ fmt_pct_ratio(r.economic_return) })
    lines << table_row("ROE / Rcp (RN/CP) %",        ->(r){ fmt_pct_ratio(r.return_on_equity) })
    lines << table_row("Écart Rcp − Re (pts)",        ->(r){
      re  = r.economic_return
      roe = r.return_on_equity
      next "—" unless re && roe
      diff = ((roe - re) * 100).round(1)
      diff > 0 ? "+#{diff}" : diff.to_s
    })
    lines << table_row("Effet de levier financier",  ->(r){ r.balance_sheet&.financial_leverage&.round(2) })
    lines << table_row("Autonomie financière %",     ->(r){ fmt_pct_ratio(r.balance_sheet&.financial_autonomy_ratio) })
    lines << table_row("Liquidité générale",         ->(r){ r.balance_sheet&.general_liquidity_ratio&.round(2) })
    lines << table_row("Liquidité réduite",          ->(r){ r.balance_sheet&.reduced_liquidity_ratio&.round(2) })
    lines << table_row("Dettes nettes / EBITDA",     ->(r){ r.debt_ratio&.round(2) })
    lines << table_row("Couverture intérêts",        ->(r){ r.interest_coverage_ratio&.round(1) })
    lines << table_row("DSO — clients (j, HT)",      ->(r){ r.days_sales_outstanding&.round(1) })
    lines << table_row("DIO — stocks (j)",           ->(r){ r.days_inventory_outstanding&.round(0) })
    lines << table_row("DPO — fournisseurs (j, large)", ->(r){
      bs      = r.balance_sheet
      is      = r.income_statement
      suppliers = (bs&.trade_payables.to_f + bs&.other_operating_liabilities.to_f)
      ebitda    = is&.ebitda_calculated
      revenue   = is&.revenue
      costs     = (ebitda && revenue) ? revenue - ebitda : nil
      (costs&.positive? && suppliers > 0) ? (suppliers / (costs * 1.20) * 365).round(0) : nil
    })
    lines << table_row("État outil industriel %",    ->(r){ fmt_pct_ratio(r.balance_sheet&.industrial_tool_ratio) })
    lines << table_row("Ratio investissement/DAP",   ->(r){ r.industrial_policy_ratio&.round(2) })
    lines << table_row("Intensité capitalistique",   ->(r){ r.capital_intensity&.round(2) })
    lines << ""

    lines << "### Flux de trésorerie"
    lines << table_header
    lines << table_row("CAF approx. (RN + DAP, M€)",   ->(r){ fmt_m((r.income_statement&.net_income.to_f + r.income_statement&.depreciation_amortization.to_f)) })
    lines << table_row("Flux exploitation (M€)",        ->(r){ fmt_m(r.cash_flow_statement&.operating_cash_flow) })
    lines << table_row("CAPEX (M€)",                    ->(r){ fmt_m(r.cash_flow_statement&.capital_expenditure) })
    lines << table_row("Free cash-flow (M€)",           ->(r){ fmt_m(r.cash_flow_statement&.free_cash_flow) })
    lines << table_row("Dividendes versés (M€)",        ->(r){ fmt_m(r.cash_flow_statement&.dividends_paid) })
    lines << ""

    # ── Diagnostic Q&A validé ─────────────────────────────────────────────
    answers = CompanyAnswer.joins(:question)
                           .where(company: @company)
                           .order("questions.position")
    if answers.any?
      lines << "## Diagnostic établi (#{answers.count} réponses validées)"
      answers.each do |ca|
        opts = Array(ca.selected_options).join(" ; ")
        lines << "Q#{ca.question.position} → #{opts}"
      end
      lines << ""
    end

    lines << "---"
    lines << ""
    lines << <<~PROMPT
      ## Mission

      Tu es un analyste financier senior. Rédige en français une **note de synthèse financière** de #{@company.name}
      en suivant **exactement** le plan ci-dessous, tel qu'il est enseigné dans les cours d'analyse financière de niveau
      grande école (HEC, ESSEC, ICCF).

      ### Plan de la note (introduction + 4 parties — titres exacts à utiliser) :

      **Introduction** (1 paragraphe)
      - Présentation du groupe : nature (familial, coté, indépendant…), activité principale, positionnement dans son secteur
      - Contexte sectoriel sur la période analysée : dynamique du marché, croissance structurelle ou non
      - Mentionner que la croissance du CA repose à la fois sur la croissance organique (volumes, prix, mix)
        ET sur des acquisitions si c'est le cas
      - Si les principaux coûts sont variables (coût des ventes, marketing, R&D), le mentionner :
        c'est un facteur favorable en cas de baisse d'activité car les charges s'ajustent plus vite

      **1. Analyse des marges**
      - Évolution du CA : TCAM, puis décomposer entre effet prix, effet volume et effet acquisitions —
        préciser lequel domine ; ne pas dire que la hausse des prix "compense" la baisse des volumes
        si le CA recule en valeur absolue
      - Hiérarchie des marges : marge brute → EBITDA → EBIT → marge nette (évolution en % et en M€)
      - Effet de ciseau : souligner en PREMIER LIEU l'effet de ciseau POSITIF de la croissance —
        quand le CA croît, la marge brute s'améliore et le poids relatif du coût des ventes diminue ;
        puis si une période de recul existe (ex. pandémie), décrire l'effet de ciseau négatif
      - Si production par assemblage pluriannuel (ex. champagne) : signaler la dérive de marge brute
        à venir sur l'exercice suivant du fait des matières premières achetées à prix élevés
      - Érosion de la marge d'exploitation : les coûts fixes ne s'ajustent pas aussi vite que la marge brute
      - Mentionner le taux d'IS apparent (IS / résultat avant IS) et qualifier s'il est normal ou non
      - Si disponible : point mort et marge de sécurité
      - Conclure explicitement que l'analyse des marges montre la **bonne gestion** du groupe

      **2. Analyse des investissements**
      - Structure des immobilisations : comparer les immobilisations incorporelles nettes (hors goodwill)
        aux immobilisations corporelles nettes — si les incorporelles dépassent les corporelles, souligner
        ce que cela révèle du modèle économique (marques, brevets, logiciels sont les vrais actifs)
      - État de l'outil industriel corporel : ratio immos corporelles nettes / brutes (jeune si > 60 %,
        vieux si < 40 %, zone intermédiaire entre les deux) ; si le ratio est dans la zone basse ou
        intermédiaire (≤ 55 %), signaler EXPLICITEMENT que les immobilisations corporelles atteignent
        un degré d'usure qui va bientôt impliquer des réinvestissements dans ce domaine
      - Politique d'investissement : ratio CAPEX total / dotations aux amortissements (> 1 = expansion) ;
        si le CAPEX en immobilisations corporelles semble faible par rapport aux amortissements,
        l'expliquer par la conjoncture (ex. 2020-2021) et/ou par la stratégie de croissance externe
        qui réduit le besoin d'investissement interne
      - BFR : souligner son poids dans l'actif économique ; si activité saisonnière, indiquer que
        seule la comparaison à même date d'une année à l'autre est pertinente
      - Stocks : souligner leur importance absolue dans l'actif et en expliquer les causes
        (gamme très large, multiples produits, volonté de ne pas perdre de ventes faute de stock disponible)
      - Rotations : DSO, DIO, DPO — lire les valeurs ANNÉE PAR ANNÉE dans le tableau ci-dessus ;
        vérifier si un ratio a connu un creux ou un pic intermédiaire qui change l'interprétation ;
        noter la valeur minimale et l'année où elle apparaît pour chaque ratio ;
        si le minimum du DSO se situe en milieu de période (pas en première ni en dernière année),
        cela indique une tendance structurelle de raccourcissement interrompue par un évènement —
        commenter la tendance structurelle ET ce qui l'a interrompue ;
        formuler la tendance et sa cause pour chacun des trois ratios ;
        si DPO progresse sur la période → dire que les fournisseurs participent davantage
        au financement des stocks
      - Intensité capitalistique (AE / CA)

      **3. Analyse des financements**
      - Approche dynamique : vérifier si les flux d'exploitation sont positifs sur toute la période ;
        vérifier si la CAF couvre les investissements — si oui, affirmer que la société autofinance
        ses investissements ; pour les versements aux actionnaires, raisonner sur l'ENSEMBLE de la
        période (pas année par année) : si la somme des flux disponibles couvre la somme des
        dividendes ET rachats d'actions versés, écrire EXACTEMENT :
        "[Société] a autofinancé ses versements aux actionnaires (dividendes et rachats d'actions)"
        — ne jamais mentionner uniquement les dividendes sans citer les rachats d'actions ;
        conclure sur le recours ou non à l'endettement externe
      - Approche statique : comparer la dette nette de la DERNIÈRE année à celle de la PREMIÈRE
        année pour dire si elle a baissé ou augmenté sur la période (ne pas se limiter à la variation
        du dernier exercice) ; commenter le ratio dette nette / EBITDA ;
        pour la couverture des intérêts, appliquer la RÈGLE IMPÉRATIVE première→dernière année :
        partir OBLIGATOIREMENT de la valeur de la PREMIÈRE année disponible — ne jamais partir d'un
        pic intermédiaire même s'il est plus récent (ex. : si couverture = 11,8x en 2022 puis pic
        à 14,9x en 2023 puis 8,1x en 2025, écrire "passant de 11,8x en 2022 à 8,1x en 2025") ;
        porter un jugement explicite sur le niveau d'endettement
      - Risque de liquidité : ratios général et réduit ; préciser que l'endettement bancaire
        et financier est MAJORITAIREMENT À LONG TERME, ce qui réduit le risque réel de liquidité ;
        distinguer risque de LIQUIDITÉ (CT) et risque de SOLVABILITÉ (LT) ;
        conclure explicitement si la société a ou non un problème de solvabilité

      **4. Analyse des rentabilités**
      - Rentabilité économique Re = EBIT(1 − t) / Actif économique, décomposée en marge × rotation ;
        RÈGLE IMPÉRATIVE : calculer Re pour CHAQUE ANNÉE en utilisant le taux d'IS de CETTE MÊME
        ANNÉE (IS de l'année / résultat courant avant IS de la même année) — ne pas appliquer un
        taux IS unique à toutes les années ; qualifier le taux d'IS : normal (~25-28 %), faible ou élevé
      - Décrire la TRAJECTOIRE COMPLÈTE de Re : progression puis rechute si c'est la réalité — ne pas
        résumer à une simple variation entre première et dernière année
      - Qualifier le niveau de Re : SATISFAISANT ou MÉDIOCRE — le dire clairement
      - Comparer Re au CMPC si disponible : si Re < CMPC, la société détruit de la valeur économique
      - Rentabilité financière Rcp = RN part du groupe / CP part du groupe
      - Lire la ligne "Écart Rcp − Re (pts)" dans le tableau des ratios ; identifier les années
        où l'écart est négatif (Rcp < Re) et celles où il est positif (Rcp > Re) ;
        si une seule année présente un écart positif très élevé par rapport aux autres, c'est
        probablement une anomalie — l'identifier et l'expliquer ; conclure sur la relation
        structurelle (hors anomalie), qui est celle que l'on observe sur les autres années
      - Si la société détient une participation financière importante comptabilisée dans les CP :
        son résultat (dividendes, plus-values) ne contribue pas à l'EBIT mais sa valeur comptable
        gonfle les CP → analyser si cela crée structurellement un écart Rcp < Re, et le dire
      - Si des rachats d'actions ont eu lieu sur une année précise : noter leur effet mécanique
        sur la Rcp de cette année-là (CP réduits) et le distinguer de la tendance structurelle
      - Effet de levier : Rcp = Re + (Re − coût apparent dette après IS) × (Dette nette / CP) ;
        conclure si l'effet est positif ou négatif pour les actionnaires
      - Si la capitalisation boursière est disponible : la comparer aux capitaux propres comptables,
        chiffrer l'écart en pourcentage ; si la capitalisation est INFÉRIEURE aux CP, écrire
        EXACTEMENT cette formulation : "En valorisant [Société] à X M€, soit Y % de moins que
        ses capitaux propres comptables, les investisseurs RECONNAISSENT que l'entreprise est
        dans une phase de destruction de valeur pour ses actionnaires." — le verbe "reconnaissent"
        est obligatoire ; bannir "reflète", "traduit une perception", "perception prudente"
      - Conclusion OBLIGATOIRE (dernier paragraphe de la section 4, commençant par "En conclusion,") :
        synthèse double perspective — actionnaires (Rcp, dividendes, signal boursier) et
        prêteurs (Re vs CMPC, couverture des intérêts, solvabilité) — la note NE PEUT PAS
        se terminer sur le seul constat de la capitalisation boursière

      ### Contraintes impératives :
      - **LONGUEUR STRICTE : 900 à 1 200 mots, titre inclus** — budget ~200 mots par section, ~100 mots pour l'introduction
        1 paragraphe par indicateur, 2 phrases maximum par paragraphe. Pas de répétitions ni de transitions superflues.
        Ne jamais mentionner le nombre de mots dans les titres.
      - Appuie-toi sur les réponses Q&A validées ci-dessus — ne contredis pas le diagnostic établi
      - Ton factuel, analytique et professionnel — chiffres en M€ ou en % à chaque affirmation
      - La note se termine par un point final après la conclusion de la section 4
      - Langue : français courant professionnel
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

  def fmt_m(value)
    return "—" unless value
    (value / 1_000_000.0).round(1).to_s
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
