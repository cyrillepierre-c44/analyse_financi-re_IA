require "net/http"
require "json"

# Agent IA en 4 phases qui enrichit le champ ia_context d'une société.
#
# Phase 1 – Audit des lacunes : analyse les données financières disponibles
#            et détermine ce qui manque pour une analyse de qualité ICCF/HEC.
# Phase 2 – Extraction documentaire : lit les CompanyDocuments attachés
#            (PDF, Excel, Word, PPT) et extrait les informations pertinentes.
# Phase 3 – Recherche web : comble les lacunes restantes via Tavily.
# Phase 4 – Génération du contexte : synthétise tout en ia_context structuré.
#
# Usage :
#   AnalyticalPreparationAgent.call(company)
#
class AnalyticalPreparationAgent
  MODEL    = "gpt-4o"
  API_BASE = "https://models.inference.ai.azure.com"

  def self.call(company)
    new(company).call
  end

  def initialize(company)
    @company = company
    @logs    = []
  end

  def call
    @company.update!(ia_context_status: "processing")

    log "=== Démarrage AnalyticalPreparationAgent pour #{@company.name} ==="

    # Phase 1 : audit
    log "Phase 1 – Audit des lacunes…"
    gaps = audit_gaps

    # Phase 2 : documents
    log "Phase 2 – Extraction documentaire…"
    doc_knowledge = extract_documents

    # Phase 3 : web (si Tavily configuré et lacunes identifiées)
    log "Phase 3 – Recherche web…"
    web_knowledge = search_web(gaps)

    # Phase 4 : génération du contexte
    log "Phase 4 – Génération du contexte ia_context…"
    new_context = generate_context(gaps, doc_knowledge, web_knowledge)

    # Phase 4b : filtrage des lacunes résolues
    log "Phase 4b – Filtrage des lacunes résolues…"
    remaining_gaps = filter_resolved_gaps(gaps, new_context)

    # Séparer gaps importants (visibles) et secondaires (structurellement introuvables)
    primary_gaps   = remaining_gaps.reject { |g| SECONDARY_GAP_PATTERNS.any? { |p| g.match?(p) } }
    secondary_gaps = remaining_gaps.select { |g| SECONDARY_GAP_PATTERNS.any? { |p| g.match?(p) } }

    log "  → #{gaps.size - remaining_gaps.size}/#{gaps.size} lacunes résolues, #{primary_gaps.size} importantes + #{secondary_gaps.size} secondaires restantes"

    @company.update!(
      ia_context:        new_context,
      ia_context_status: "ready",
      ia_context_gaps:   primary_gaps.join("\n")
    )

    log "=== Terminé avec succès ==="
    new_context

  rescue => e
    @company.update!(ia_context_status: "error")
    Rails.logger.error "[AnalyticalPreparationAgent] #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    raise
  end

  private

  # ── PHASE 1 : AUDIT ──────────────────────────────────────────────────────────
  def audit_gaps
    financial_summary = build_financial_summary
    existing_context  = @company.ia_context.to_s

    prompt = <<~PROMPT
      Tu es un analyste financier expert (formation ICCF/HEC).
      On prépare une analyse financière approfondie de la société #{@company.name}.

      Voici le résumé des données financières disponibles :
      #{financial_summary}

      Voici le contexte qualitatif déjà disponible :
      #{existing_context.presence || "(aucun)"}

      DONNÉES DÉJÀ CALCULÉES PAR L'APPLICATION — ne jamais les signaler comme lacunes :
      - Tous les SIG : CA, EBITDA, EBIT, résultat net, marges brute/EBITDA/EBIT/nette
      - Ratios de rotation : DSO, DPO, DIO (rotation des stocks en jours)
      - BFR, actif économique, intensité capitalistique
      - CAPEX, dotations aux amortissements, ratio CAPEX/DAP
      - Dette nette, ratio DN/EBITDA, gearing (DN/CP)
      - Couverture des intérêts (EBIT / charges financières nettes)
      - Rentabilité économique (Re), rentabilité financière (Rcp), écart Rcp − Re
      - Free cash flow, CAF, flux opérationnels
      - Ratios de liquidité générale et réduite
      - Taux d'IS apparent

      Ta tâche : identifier UNIQUEMENT les lacunes qualitatives ou données externes
      que l'application ne peut pas calculer seule, et qui sont absentes du contexte
      qualitatif ci-dessus. Chercher parmi :
      - CMPC / WACC
      - Taux d'intérêt moyen sur la dette
      - Capitalisation boursière et comparaison aux capitaux propres
      - Notation de crédit
      - Lignes de crédit confirmées non utilisées
      - Actionnariat détaillé (% par actionnaire nommé, type familial/fonds/public)
      - Politique de rachats d'actions (montants, fréquence)
      - Participations importantes au bilan (société, valeur comptable, nature)
      - Positionnement sectoriel, concurrents principaux, parts de marché
      - Acquisitions réalisées pendant la période analysée
      - Saisonnalité de l'activité et impact sur le BFR
      - Événements exceptionnels significatifs sur la période
      - Impact des variations de change sur les résultats
      - Structure des coûts (fixe vs variable, principaux postes)

      RÈGLE IMPORTANTE : si le contexte contient déjà une valeur précise, une estimation
      sectorielle ("~X %") ou une approximation raisonnée pour un point, NE PAS le signaler
      comme lacune. Une lacune = absence totale d'information sur le sujet dans le contexte.

      Retourne une liste JSON (tableau de strings), chaque élément étant
      une lacune précise à combler. Si tout est déjà disponible, retourne [].

      Réponds UNIQUEMENT avec le tableau JSON, sans texte autour.
    PROMPT

    response = llm_call(prompt, max_tokens: 1000)
    JSON.parse(response.match(/\[.*\]/m)&.to_s || "[]")
  rescue JSON::ParserError
    []
  end

  # ── PHASE 2 : EXTRACTION DOCUMENTAIRE ────────────────────────────────────────
  def extract_documents
    documents = @company.company_documents.includes(file_attachment: :blob)
    return "" if documents.empty?

    parts = []
    documents.each do |doc|
      next unless doc.file.attached?

      log "  → Extraction : #{doc.filename} (#{doc.human_type})"
      begin
        raw_text = DocumentTextExtractor.new(doc).extract
        doc.update!(status: "processed", extracted_text: raw_text.truncate(50_000))
        parts << "=== Document : #{doc.filename} (#{doc.human_type}) ===\n#{raw_text.truncate(10_000)}"
      rescue => e
        doc.update!(status: "error", processing_notes: e.message)
        log "  ✗ Erreur extraction #{doc.filename}: #{e.message}"
      end
    end

    return "" if parts.empty?

    # Résumer le contenu extrait via LLM pour ne garder que l'essentiel
    summarize_documents(parts.join("\n\n"))
  end

  def summarize_documents(raw_text)
    prompt = <<~PROMPT
      Voici le contenu extrait de documents financiers concernant #{@company.name}.
      Extrait UNIQUEMENT les faits utiles pour une analyse financière :
      chiffres clés, gouvernance, stratégie, actionnariat, dividendes, rachats,
      CMPC, capitalisation, participations au bilan, événements significatifs.

      FORMAT : bullet points uniquement, zéro paragraphe. Max 1500 caractères.
      Conserve les chiffres et dates précis.

      CONTENU BRUT :
      #{raw_text.truncate(40_000)}
    PROMPT

    llm_call(prompt, max_tokens: 600)
  end

  # Gaps secondaires : structurellement introuvables (données confidentielles non publiées).
  # Passés à generate_context pour enrichissement LLM, mais exclus de ia_context_gaps.
  SECONDARY_GAP_PATTERNS = [
    /taux d.intérêt/i,
    /lignes de crédit/i,
    /variations de change/i,
    /structure.*coûts/i,
    /coûts.*fix/i,
    /répartition.*coûts/i,
    /postes de coûts/i,
    /valeur comptable.*participation/i,
    /dividendes reçus.*participation/i
  ].freeze

  # Alias pour search_web (même liste — pas de recherche Tavily non plus)
  WEB_SKIP_PATTERNS = SECONDARY_GAP_PATTERNS

  # ── PHASE 3 : RECHERCHE WEB ───────────────────────────────────────────────────
  def search_web(gaps)
    return "" if gaps.empty?
    return "" unless ENV["TAVILY_API_KEY"].present?

    searcher = WebSearchService.new
    results  = []

    # Toutes les lacunes sont recherchées, sauf celles que Tavily ne peut pas résoudre
    gaps.each do |gap|
      if WEB_SKIP_PATTERNS.any? { |p| gap.match?(p) }
        log "  → Skip web (données non publiées) : #{gap}"
        next
      end
      query = gap_to_query(gap)
      log "  → Recherche : #{query}"
      hits  = searcher.search(query, max_results: 5)
      results.concat(hits)
    end

    # Recherche générale actionnariat + gouvernance
    general_hits = searcher.search(
      "#{@company.name} shareholders ownership structure annual report",
      max_results: 5
    )
    results.concat(general_hits)

    return "" if results.empty?

    # Dédupliquer par URL — un seul appel summarize_web (budget API)
    results.uniq! { |r| r[:url] }

    web_text = results.map { |r| "#{r[:title]}\n#{r[:content]}" }.join("\n\n---\n\n")
    summarize_web(web_text)
  end

  def summarize_web(web_text)
    prompt = <<~PROMPT
      Voici des extraits de pages web concernant #{@company.name}.

      MISSION : extraire TOUS les faits utiles pour combler des lacunes d'analyse financière.
      En particulier : actionnariat (% par actionnaire nommé), notation de crédit, CMPC,
      capitalisation boursière, lignes de crédit, taux d'intérêt moyen, rachats d'actions,
      participations au bilan, concurrents et parts de marché, variations de change,
      structure des coûts (part fixe/variable).

      RÈGLE ABSOLUE : si un fait est présent dans les extraits, le retranscrire avec le
      chiffre EXACT et la date. Ne jamais résumer en "information non disponible" si
      l'extrait contient la donnée.

      FORMAT : bullet points uniquement, zéro paragraphe. Max 1 500 caractères.
      Élimine le bruit marketing. Conserve les chiffres et dates précis.

      CONTENU WEB :
      #{web_text.truncate(24_000)}
    PROMPT

    llm_call(prompt, max_tokens: 700)
  end

  # Transforme une lacune verbeuse en requête de recherche concise et efficace
  def gap_to_query(gap)
    # Supprimer les explications entre parenthèses et les descriptions trop longues
    clean = gap.gsub(/\(.*?\)/, '').strip.truncate(60, omission: '')
    "#{@company.name} #{clean}"
  end

  # ── PHASE 4b : FILTRAGE DES LACUNES RÉSOLUES ─────────────────────────────────
  def filter_resolved_gaps(gaps, context)
    return [] if gaps.empty?

    prompt = <<~PROMPT
      Voici une liste de lacunes d'information identifiées pour l'analyse financière
      de #{@company.name}, et le contexte analytique finalement généré.

      LACUNES IDENTIFIÉES :
      #{gaps.map.with_index(1) { |g, i| "#{i}. #{g}" }.join("\n")}

      CONTEXTE GÉNÉRÉ :
      #{context.truncate(8_000)}

      Ta tâche : identifier quelles lacunes restent NON RÉSOLUES dans le contexte généré.
      - Lacune RÉSOLUE = le contexte contient des informations substantielles sur ce point,
        y compris une estimation sectorielle ("~X %"), une approximation raisonnée, ou une
        valeur partielle. Le critère est : "un analyste peut travailler avec cette donnée".
      - Lacune NON RÉSOLUE = le contexte marque explicitement "n/d" sans chiffre, ou ne
        mentionne pas du tout le sujet.

      Sois INDULGENT : si la donnée est présente à 70 % (ex : actionnariat avec les
      principaux actionnaires et leurs %, même sans détail exhaustif), marque-la RÉSOLUE.

      Retourne UNIQUEMENT un tableau JSON des lacunes encore non résolues (strings, formulées
      exactement comme dans la liste ci-dessus). Sans texte autour.
    PROMPT

    response = llm_call(prompt, max_tokens: 800)
    JSON.parse(response.match(/\[.*\]/m)&.to_s || "[]")
  rescue JSON::ParserError
    gaps
  end

  # ── PHASE 4 : GÉNÉRATION DU CONTEXTE ─────────────────────────────────────────
  def generate_context(gaps, doc_knowledge, web_knowledge)
    existing_context  = @company.ia_context.to_s
    financial_summary = build_financial_summary

    # Extraire les marqueurs techniques (Q18_ANSWER, FRANCE_PCT, NOTE_*, etc.) pour les réinjecter après génération
    # Ces marqueurs sont des données H1 ou spécifiques non présentes dans les rapports annuels.
    technical_markers = existing_context.scan(/^(?:Q\d+_ANSWER|FRANCE_PCT|NOTE_[A-Z_]+)\s*:.*$/i).join("\n")

    prompt = <<~PROMPT
      Tu es un analyste financier expert (formation ICCF/HEC).
      Génère un BRIEF DE DONNÉES pour l'analyse financière de #{@company.name}.

      RÔLE : ce brief est la SEULE source d'information qualitative pour l'IA qui rédigera
      l'analyse financière et répondra au Q&A. Il doit contenir TOUT ce qui n'est pas
      calculable à partir des états financiers : actionnariat, secteur, stratégie, CMPC,
      capitalisation boursière, participations au bilan, risques, événements significatifs.

      FORMAT : bullet points pour les données simples ; 2-3 phrases pour les sujets complexes
      (secteur, stratégie, participations). Aucune répétition de chiffres déjà dans les états financiers.
      CIBLE : 3 000 à 3 500 caractères — vise la borne haute pour maximiser la richesse du contexte.

      RÈGLE ABSOLUE — INTERDICTION DU "n/d" :
      Tu as accès à trois sources : (1) les résultats de recherches web ci-dessous,
      (2) tes connaissances générales sur #{@company.name}, (3) les estimations sectorielles.
      "n/d" est STRICTEMENT INTERDIT sauf si ces trois sources sont toutes silencieuses sur
      le point en question. Dans tous les autres cas :
      - Si tu as une valeur précise (web ou connaissance générale) → inscris-la avec sa source
      - Si tu n'as qu'une fourchette sectorielle → écris "~X % (estimation sectorielle)"
      - Si tu peux déduire une approximation → écris "~X (estimé d'après...)"
      Pour les données publiquement connues (actionnariat Volkswagen/Porsche, participation
      Sanofi/L'Oréal, famille Nonancourt/Laurent-Perrier, note de crédit publiée, etc.) :
      les inscrire directement sans attendre qu'elles apparaissent dans les sources fournies.

      DONNÉES FINANCIÈRES DISPONIBLES (ne pas répéter) :
      #{financial_summary}

      CONTEXTE EXISTANT (à conserver/améliorer) :
      #{existing_context.presence || "(aucun)"}

      INFORMATIONS ISSUES DES DOCUMENTS :
      #{doc_knowledge.presence || "(aucun)"}

      INFORMATIONS ISSUES DE RECHERCHES WEB :
      #{web_knowledge.presence || "(aucune)"}

      LACUNES À COMBLER SI POSSIBLE :
      #{gaps.map { |g| "- #{g}" }.join("\n").presence || "(aucune)"}

      STRUCTURE OBLIGATOIRE (respecter ces sections dans cet ordre) :

      ## Identité
      - Actionnariat : [type exact : familial/coté/fonds/public] ([famille ou fonds], [%])
      - Cotation : [place boursière ou "non coté"]
      - Clôture fiscale : [mois]
      - Saisonnalité : [oui/non + raison en 5 mots max]
      - CMPC estimé : [X % — utilise le CMPC sectoriel si non disponible explicitement]
      - Capitalisation boursière : [X M€] ([mois année]) = [Y %] des CP FY[N] ou n/d
      - Rachats d'actions : [oui, ~X M€/an ou ~X %] / [non]

      ## Secteur & marché
      - Marché : [nom + taille approximative + tendance structurelle de croissance ou stagnation]
      - Position concurrentielle : [rang ou description — leader/challenger/niche]
      - Concurrents principaux : [liste avec précision si possible]
      - Tendance volumes : [croissance X %/stagnation/déclin + cause principale]
      - Tendance prix moyens : [hausse/stable/baisse + raison si connue]
      - Cyclicité : [oui/non + facteur principal]
      - Structure des coûts : [principaux postes, part variable vs fixe si connue]

      ## Stratégie & croissance
      - Moteurs de croissance CA : [organique (vol/prix/mix) / acquisitions — précise lequel domine]
      - Acquisitions réalisées PENDANT la période analysée uniquement : [liste avec année et montant si connu] ou aucune
      - Montée en gamme : [oui/non + exemple produit ou marque]

      ## Distribution aux actionnaires
      - Dividendes : [montant M€/an ou €/action, ou taux de distribution approximatif]
      - Rachats d'actions : [oui/non, montant ou % capital par an]

      ## Participations importantes au bilan — CRITIQUE POUR L'ANALYSE
      Les dividendes reçus d'une participation comptent dans le résultat NET mais PAS dans l'EBIT.
      La valeur comptable de la participation gonfle les capitaux propres.
      Ces deux effets créent structurellement un écart Rcp < Re — l'omettre fausse l'analyse.
      UTILISE TES CONNAISSANCES GÉNÉRALES sur #{@company.name} pour identifier toute participation significative.
      - [Nom société] : valeur comptable ~[X M€], dividendes reçus ~[X M€/an] → dans RN mais PAS dans EBIT, gonfle CP
      (si aucune participation significative après vérification : "aucune")

      ## Financement
      - Structure dette : [LT dominante / CT / mixte — précise si possible LT vs CT en %]
      - Lignes de crédit confirmées non utilisées : [X M€] ou n/d
      - Note de crédit : [notation agence] ou n/d

      ## Risques clés
      - [3 à 6 bullets, max 12 mots chacun — risques sectoriels et propres à la société]

      ## Événements clés (PENDANT la période analysée uniquement)
      - [Année] : [événement factuel concis]
      (ne pas citer d'événements postérieurs à la dernière année du tableau financier)

      Génère uniquement le brief, sans introduction ni conclusion :
    PROMPT

    result = llm_call(prompt, max_tokens: 2200)

    # Réinjecter les marqueurs techniques s'ils ont disparu du contexte généré
    if technical_markers.present?
      missing = technical_markers.split("\n").reject { |m| result.include?(m.split(":").first) }
      result += "\n\n---\n#{missing.join("\n")}\n" if missing.any?
    end

    result
  end

  # ── DONNÉES FINANCIÈRES RÉSUMÉES ──────────────────────────────────────────────
  def build_financial_summary
    reports = @company.financial_reports
                      .includes(:income_statement, :balance_sheet, :cash_flow_statement)
                      .order(:fiscal_year)

    return "Aucun rapport financier disponible." if reports.empty?

    lines = ["Société : #{@company.name} | Norme : #{@company.accounting_standard&.upcase}"]
    lines << "Exercice fiscal : clôture mois #{@company.fiscal_year_end_month}"
    lines << ""

    reports.each do |r|
      is  = r.income_statement
      bs  = r.balance_sheet
      cfs = r.cash_flow_statement
      lines << "── FY#{r.fiscal_year} ──"
      lines << "  CA: #{fmt(is&.revenue)} | EBITDA: #{fmt(is&.ebitda_calculated)} | Résultat net: #{fmt(is&.net_income)}" if is
      lines << "  Total actif: #{fmt(bs&.total_assets)} | Dettes LT: #{fmt(bs&.lt_financial_debt)} | Capitaux propres: #{fmt(bs&.total_equity)}" if bs
      lines << "  FCF: #{fmt(cfs&.free_cash_flow)} | CAPEX: #{fmt(cfs&.capital_expenditure)}" if cfs
    end

    lines.join("\n")
  end

  def fmt(val)
    return "n/d" if val.nil?
    n = val.to_f
    return "#{(n / 1_000_000).round(1)} M€" if n.abs >= 1_000_000
    return "#{(n / 1_000).round(0)} k€"     if n.abs >= 1_000
    "#{n.round(0)} €"
  end

  # ── APPEL LLM ─────────────────────────────────────────────────────────────────
  def llm_call(prompt, max_tokens: 2000, retries: 3)
    uri  = URI("#{API_BASE}/chat/completions")
    key  = ENV.fetch("GITHUB_KEY")

    body = {
      model:       MODEL,
      messages:    [ { role: "user", content: prompt } ],
      max_tokens:  max_tokens,
      temperature: 0.3
    }

    req                  = Net::HTTP::Post.new(uri)
    req["Content-Type"]  = "application/json"
    req["Authorization"] = "Bearer #{key}"
    req.body             = body.to_json

    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 120) do |h|
      h.request(req)
    end

    if res.code.to_i == 429 && retries > 0
      raw_wait = res.body.match(/Please wait (\d+) seconds/i)&.captures&.first&.to_i
      wait = [ raw_wait || 65, 120 ].min  # plafonné à 120s — évite les timestamps Unix mal parsés
      log "  ⚠ Rate limit 429 — pause #{wait}s (#{retries} essai(s) restant(s))…"
      sleep(wait + 2)
      return llm_call(prompt, max_tokens: max_tokens, retries: retries - 1)
    end

    raise "LLM API error #{res.code}: #{res.body.truncate(200)}" unless res.is_a?(Net::HTTPSuccess)

    parsed = JSON.parse(res.body)
    parsed.dig("choices", 0, "message", "content").to_s
  end

  def log(msg)
    @logs << msg
    Rails.logger.info "[AnalyticalPreparationAgent] #{msg}"
  end
end
