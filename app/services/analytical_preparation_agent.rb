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
    log "  → #{gaps.size - remaining_gaps.size}/#{gaps.size} lacunes résolues, #{remaining_gaps.size} restantes"

    @company.update!(
      ia_context:        new_context,
      ia_context_status: "ready",
      ia_context_gaps:   remaining_gaps.join("\n")
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

      Ta tâche : identifier toutes les lacunes d'information qui empêcheraient
      de répondre correctement aux 25 critères d'une analyse ICCF/HEC :
      - Marges (brute, EBITDA, nette) et leur évolution
      - Investissements, BFR, DSO, DPO, rotation stocks
      - Structure financière (dette, gearing, autofinancement)
      - Rentabilité (ROE, ROCE, création/destruction de valeur)
      - Contexte sectoriel, positionnement, concurrence
      - Gouvernance, actionnariat
      - Dividendes, rachats d'actions
      - Événements exceptionnels récents

      Retourne une liste JSON (tableau de strings), chaque élément étant
      une lacune précise à combler. Exemple :
      ["Positionnement concurrentiel de #{@company.name} dans son secteur",
       "Politique de dividendes historique",
       "Taux d'intérêt moyen sur la dette"]

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

  # ── PHASE 3 : RECHERCHE WEB ───────────────────────────────────────────────────
  def search_web(gaps)
    return "" if gaps.empty?
    return "" unless ENV["TAVILY_API_KEY"].present?

    searcher = WebSearchService.new
    results  = []

    # Recherches ciblées sur les lacunes les plus importantes (max 4)
    priority_gaps = gaps.first(4)
    priority_gaps.each do |gap|
      query   = "#{@company.name} #{gap}"
      log "  → Recherche : #{query}"
      hits    = searcher.search(query, max_results: 3)
      results.concat(hits)
    end

    # Recherche générale sur la société
    general_hits = searcher.search("#{@company.name} résultats financiers secteur analyse", max_results: 3)
    results.concat(general_hits)

    return "" if results.empty?

    # Synthèse des résultats web
    web_text = results.map { |r| "#{r[:title]}\n#{r[:content]}" }.join("\n\n---\n\n")
    summarize_web(web_text)
  end

  def summarize_web(web_text)
    prompt = <<~PROMPT
      Voici des extraits de pages web concernant #{@company.name}.
      Extrait UNIQUEMENT les faits utiles pour une analyse financière :
      positionnement sectoriel, tendances marché, concurrents, CMPC, capitalisation,
      rachats d'actions, participations, événements récents.

      FORMAT : bullet points uniquement, zéro paragraphe. Max 1000 caractères.
      Élimine le bruit marketing. Conserve chiffres et dates précis.

      CONTENU WEB :
      #{web_text.truncate(30_000)}
    PROMPT

    llm_call(prompt, max_tokens: 400)
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
      - Lacune RÉSOLUE = le contexte contient des informations substantielles sur ce point.
      - Lacune NON RÉSOLUE = le contexte ne mentionne pas le sujet, ou précise explicitement
        que l'information n'est pas disponible.

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

    # Extraire les marqueurs techniques (Q18_ANSWER, FRANCE_PCT, etc.) pour les réinjecter après génération
    # Ces marqueurs sont des données H1 ou spécifiques non présentes dans les rapports annuels.
    technical_markers = existing_context.scan(/^(?:Q\d+_ANSWER|FRANCE_PCT)\s*:.*$/i).join("\n")

    prompt = <<~PROMPT
      Tu es un analyste financier expert (formation ICCF/HEC).
      Génère un BRIEF DE DONNÉES pour l'analyse financière de #{@company.name}.

      RÔLE DE CE DOCUMENT : ce n'est pas une analyse, c'est une base de faits
      structurée que l'IA lira en entier pour répondre au Q&A et rédiger l'analyse.
      FORMAT OBLIGATOIRE : bullet points uniquement — zéro grande phrase, zéro paragraphe.
      LIMITE STRICTE : 3 500 caractères maximum (priorité à la densité d'information).

      DONNÉES FINANCIÈRES DISPONIBLES :
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
      - CMPC estimé : [X %] ou n/d
      - Capitalisation boursière : [X M€] ([mois année]) = [Y %] des CP FY[N] ou n/d
      - Rachats d'actions : [oui, ~X M€/an ou ~X %] / [non]

      ## Secteur & marché
      - Marché : [nom + taille si connu]
      - Position concurrentielle : [rang ou description courte]
      - Concurrents principaux : [liste]
      - Tendance volumes : [croissance X %/stagnation/déclin + cause]
      - Tendance prix moyens : [hausse/stable/baisse]
      - Cyclicité : [oui/non + facteur principal]

      ## Stratégie & croissance
      - Moteurs de croissance CA : [organique (vol/prix/mix) / acquisitions]
      - Acquisitions réalisées PENDANT la période analysée uniquement : [liste avec année] ou aucune
      - Montée en gamme : [oui/non + exemple produit]

      ## Distribution aux actionnaires
      - Dividendes : [X M€/an approx ou politique]
      - Rachats d'actions : [oui/non, montant ou % capital]

      ## Participations importantes au bilan
      - [Nom société] : valeur comptable ~[X M€], dividendes ~[X M€/an] → dans RN mais PAS dans EBIT, gonfle CP
      (si aucune participation significative : "aucune")

      ## Financement
      - Structure dette : [LT dominante / CT / mixte]
      - Lignes de crédit confirmées non utilisées : [X M€] ou n/d
      - Note de crédit : [notation] ou n/d

      ## Risques clés
      - [un bullet par risque, max 10 mots chacun]

      ## Événements clés (PENDANT la période analysée uniquement)
      - [Année] : [événement factuel]
      (ne pas citer d'événements postérieurs à la dernière année du tableau financier)

      Génère uniquement le brief, sans introduction ni conclusion :
    PROMPT

    result = llm_call(prompt, max_tokens: 1800)

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
