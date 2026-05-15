require "pdf/reader"
require "base64"
require "shellwords"
require "fileutils"

# Service tout-en-un : lit un PDF financier, extrait les infos société
# ET toutes les données financières (multi-années), puis crée tout en base.
#
# Usage :
#   company = CompanyPdfImporter.call(pdf_path: "/tmp/file.pdf")
#   # => Company avec ses FinancialReports attachés
#
class CompanyPdfImporter
  MODEL = "gpt-4o"

  def self.call(...)
    new(...).call
  end

  def initialize(pdf_path:)
    @pdf_path = pdf_path
  end

  # Seuil pour un PDF entièrement graphique (texte global < N chars)
  TEXT_THRESHOLD = 2000
  # Seuil pour détecter des pages financières graphiques dans un PDF mixte
  FINANCIAL_PAGE_MIN_CHARS = 300

  def call
    pages_text = extract_pages_text
    text       = pages_text.join("\n")

    data = if needs_vision?(text, pages_text)
             Rails.logger.info "[CompanyPdfImporter] Mode Vision activé (texte total: #{text.length} chars)"
             parse_with_vision
           else
             prioritized = prioritize_financial_pages(pages_text)
             Rails.logger.info "[CompanyPdfImporter] Mode texte (#{text.length} chars → #{prioritized.length} après priorisation)"
             parse_with_llm(prioritized)
           end

    save_to_database(data)
  end

  private

  # ── 1. EXTRACTION TEXTE ────────────────────────────────────────────────

  def extract_pages_text
    PDF::Reader.new(@pdf_path).pages.map(&:text)
  rescue => e
    raise "Erreur lecture PDF : #{e.message}"
  end

  # Réordonne les pages pour que les tables financières passent en premier dans
  # la fenêtre de 24 000 chars. La page de couverture (index 0) est toujours
  # conservée en tête pour le nom société / date de clôture.
  def prioritize_financial_pages(pages)
    return pages.join("\n") if pages.size <= 3

    cover      = pages.first
    rest       = pages.drop(1)

    financial_re = /chiffre.{0,10}affaires|compte.{0,10}r[ée]sultat|bilan|flux.{0,10}tr[ée]sorerie|
                    r[ée]sultat.{0,10}net|capitaux.{0,10}propres|total.{0,10}actif|
                    \d[\d\s]{2,}\d[\d\s]{2,}\d/xi

    scored = rest.map do |page|
      digits       = page.scan(/\d+/).sum(&:length).to_f
      fin_matches  = page.scan(financial_re).size
      score        = digits / (page.length + 1) * 100 + fin_matches * 5
      [ score, page ]
    end

    ordered = scored.sort_by { |score, _| -score }.map { |_, page| page }

    ([cover] + ordered).join("\n")
  end

  # PDF totalement graphique → vision
  # PDF mixte où les pages financières sont des images → vision aussi
  # Tableau multi-années → vision (texte extrait perd l'alignement des colonnes)
  def needs_vision?(text, pages_text)
    return true if text.length < TEXT_THRESHOLD

    # Tableau multi-années détecté : 3 années ou plus en séquence dans le texte
    # (ex: "2016  2017  2018  2019  2020") → l'extraction texte perd l'alignement
    if pages_text.size > 5 && text.match?(/20\d{2}\s+20\d{2}\s+20\d{2}/)
      Rails.logger.info "[CompanyPdfImporter] Tableau multi-années détecté → mode Vision"
      return true
    end

    # Pages qui semblent être des tableaux financiers (titre court + chiffres attendus)
    financial_title_re = /états financiers|compte de résultat|bilan|flux de trésorerie|annexe \d/i
    pages_text.each do |t|
      return true if t.match?(financial_title_re) && t.length < FINANCIAL_PAGE_MIN_CHARS
    end

    # Pages quasi-vides (< 100 chars) qui contiennent une image → PDF mixte
    return true if image_pages_detected?

    false
  end

  # Utilise PyMuPDF (fitz) pour détecter les pages avec images et peu de texte
  def image_pages_detected?
    script = <<~PY
      import fitz, sys
      doc = fitz.open(sys.argv[1])
      count = sum(1 for p in doc if len(p.get_images()) > 0 and len(p.get_text()) < 150)
      print(count)
    PY
    result = `python3 -c #{Shellwords.escape(script)} #{Shellwords.escape(@pdf_path)} 2>/dev/null`.strip.to_i
    result > 0
  rescue
    false
  end

  def count_pages
    PDF::Reader.new(@pdf_path).page_count
  rescue
    0
  end

  # ── 2a. MODE TEXTE ────────────────────────────────────────────────────

  def parse_with_llm(text)
    call_api(messages: [ { role: "user", content: build_prompt(text) } ])
  end

  # ── 2b. MODE VISION (PDF graphique / tableaux non-texte) ──────────────
  # Deux passes distinctes : A = IS, B = CFS + Bilan.
  # Chaque passe reçoit les pages classifiées et un prompt ciblé.

  def parse_with_vision
    tmp_dir = Rails.root.join("tmp", "pdf_pages_#{SecureRandom.hex(6)}")
    FileUtils.mkdir_p(tmp_dir)

    begin
      total_pages = count_pages

      # ── Miniatures 72 dpi pour détecter les pages financières ──
      system("gs -dNOPAUSE -dBATCH -sDEVICE=pnggray -r72 " \
             "-sOutputFile=#{tmp_dir}/thumb_%03d.png #{Shellwords.escape(@pdf_path)} " \
             ">/dev/null 2>&1")

      thumbs = Dir["#{tmp_dir}/thumb_*.png"].sort
      raise "Ghostscript n'a produit aucune image" if thumbs.empty?

      pages_text_local = extract_pages_text rescue []
      fin_pages = detect_financial_page_numbers(pages_text_local, total_pages)

      # Fallback scout visuel si le texte n'a rien détecté (PDF image pur)
      if fin_pages.empty?
        thumb_contents = thumbs.first(20).map do |path|
          b64 = Base64.strict_encode64(File.binread(path))
          { type: "image_url", image_url: { url: "data:image/png;base64,#{b64}", detail: "low" } }
        end
        scout = call_api(
          messages: [{
            role: "user",
            content: [
              { type: "text",
                text: "Document de #{total_pages} pages. Retourne UNIQUEMENT ce JSON : " \
                      "{\"financial_pages\": [numéros des pages contenant des tableaux chiffrés " \
                      "(compte de résultat, bilan, flux de trésorerie — PAS les pages de texte narratif)]}" }
            ] + thumb_contents
          }],
          max_tokens: 150
        )
        fin_pages = Array(scout["financial_pages"]).map(&:to_i).select { |n| n >= 1 && n <= total_pages }
        fin_pages = ([(total_pages / 2), 1].max..[total_pages, (total_pages / 2) + 5].min).to_a if fin_pages.empty?
      end

      target_pages = fin_pages.uniq.sort.first(8)
      Rails.logger.info "[CompanyPdfImporter] Pages financières : #{target_pages.inspect}"

      # ── Haute résolution sur toutes les pages cibles ──
      target_pages.each do |num|
        system("gs -dNOPAUSE -dBATCH -sDEVICE=png16m -r200 " \
               "-dFirstPage=#{num} -dLastPage=#{num} " \
               "-sOutputFile=#{tmp_dir}/hires_#{format('%03d', num)}.png #{Shellwords.escape(@pdf_path)} " \
               ">/dev/null 2>&1")
      end

      # Page couverture (basse résolution) pour contexte société
      cover_contents = thumbs.first(1).map do |path|
        b64 = Base64.strict_encode64(File.binread(path))
        { type: "image_url", image_url: { url: "data:image/png;base64,#{b64}", detail: "low" } }
      end

      # Classifie les pages en IS vs CFS+Bilan
      is_pages, cfs_pages = classify_financial_pages(pages_text_local, target_pages)
      Rails.logger.info "[CompanyPdfImporter] IS pages: #{is_pages.inspect} | CFS+Bilan pages: #{cfs_pages.inspect}"

      # ── Passe A : Compte de résultat ──
      is_contents = build_hires_contents(is_pages, tmp_dir, thumbs)
      data_a = call_api(
        messages: [{
          role: "user",
          content: [ { type: "text", text: build_vision_income_prompt } ] + cover_contents + is_contents
        }],
        max_tokens: 8192
      )

      # ── Passe B : Tableau de flux + Bilan ──
      cfs_contents = build_hires_contents(cfs_pages, tmp_dir, thumbs)
      if cfs_contents.any?
        Rails.logger.info "[CompanyPdfImporter] Passe B (CFS+Bilan) : #{cfs_pages.length} pages"
        data_b = call_api(
          messages: [{
            role: "user",
            content: [ { type: "text", text: build_vision_cfs_bilan_prompt } ] + cover_contents + cfs_contents
          }],
          max_tokens: 8192
        )
        merge_financial_data(data_a, data_b)
      else
        Rails.logger.info "[CompanyPdfImporter] Pas de pages CFS/Bilan distinctes — passe unique"
        data_a
      end
    ensure
      FileUtils.rm_rf(tmp_dir)
    end
  end

  # ── 2c. APPEL API COMMUN ─────────────────────────────────────────────

  def call_api(messages:, max_tokens: 8192)
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
    normalize_json(parsed)
  rescue JSON::ParserError => e
    raise "JSON invalide : #{e.message}"
  end

  # Normalise les variantes de JSON que le LLM peut retourner
  def normalize_json(data)
    root_unit = data["unit"]

    years = (data["years"] || []).map do |entry|
      # fiscal_year peut être "2024-2025" → on prend la 2e année (clôture)
      fy_raw = entry.dig("meta", "fiscal_year") || entry["fiscal_year"]
      fy = case fy_raw.to_s
           when /(\d{4})-(\d{4})/ then $2.to_i  # "2024-2025" → 2025
           else fy_raw.to_i
           end

      # unit peut être dans meta ou à la racine
      unit = entry.dig("meta", "unit") || root_unit || 1

      # Construire un entry normalisé avec meta complet
      meta = (entry["meta"] || {}).merge(
        "fiscal_year" => fy,
        "unit"        => unit,
        "period_end_date"     => entry.dig("meta", "period_end_date"),
        "accounting_standard" => entry.dig("meta", "accounting_standard") || data.dig("company", "accounting_standard"),
        "is_consolidated"     => entry.dig("meta", "is_consolidated").nil? ? data.dig("company", "is_consolidated") : entry.dig("meta", "is_consolidated"),
        "income_format"       => normalize_income_format(entry.dig("meta", "income_format")) || "fonction"
      )

      # Si le LLM a mis les champs financiers directement dans l'entrée (pas imbriqués)
      is_flat = entry["income_statement"].nil? && (entry["revenue"] || entry["net_income"])

      if is_flat
        entry.merge(
          "meta"              => meta,
          "income_statement"  => extract_flat_income(entry),
          "balance_sheet"     => extract_flat_balance(entry),
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
      "revenue"                   => e["revenue"],
      "gross_margin"              => e["gross_margin"],
      "cost_of_sales"             => e["cost_of_sales"],
      "distribution_marketing_costs" => e["distribution_marketing_costs"] || e["frais_commerciaux"],
      "administrative_costs"      => e["administrative_costs"] || e["frais_administratif"],
      "ebit"                      => e["ebit"] || e["operating_result"],
      "financial_expenses"        => e["financial_expenses"] || e["cout_endettement_net"],
      "financial_income"          => e["financial_income"],
      "income_tax"                => e["income_tax"] || e["impot"],
      "net_income"                => e["net_income"] || e["resultat_net"],
      "minority_interests"        => e["minority_interests"] || e["interets_minoritaires"],
      "personnel_expenses"        => e["personnel_expenses"],
      "depreciation_amortization" => e["depreciation_amortization"] || e["dotations"],
    }
  end

  def extract_flat_balance(e)
    {
      "total_assets"      => e["total_assets"],
      "total_equity"      => e["total_equity"] || e["capitaux_propres"],
      "lt_financial_debt" => e["lt_financial_debt"],
      "st_financial_debt" => e["st_financial_debt"],
      "total_inventory"   => e["total_inventory"] || e["stocks"],
      "trade_receivables" => e["trade_receivables"] || e["clients"],
      "trade_payables"    => e["trade_payables"] || e["fournisseurs"],
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

  # ── 3. PROMPT ─────────────────────────────────────────────────────────

  def build_prompt(text)
    <<~PROMPT
      Tu es un expert-comptable et analyste financier.
      Analyse le document financier suivant et extrais TOUTES les informations dans un JSON structuré.

      ## Document
      #{text.truncate(24_000)}

      ## Instructions générales
      - Retourne UNIQUEMENT un bloc JSON valide (aucune explication autour).
      - Utilise `null` pour toute valeur absente ou illisible.
      - Retourne les montants EXACTEMENT tels qu'écrits dans le document, sans les convertir.
      - Si le document indique "En millions d'euros", retourne 305.6 (pas 305600000) et indique `"unit": 1000000` dans meta.
      - Si le document indique "En milliers d'euros", retourne 305600 (pas 305600000) et indique `"unit": 1000` dans meta.
      - Si les montants sont déjà en euros, indique `"unit": 1` dans meta.
      - Les montants négatifs sont des nombres négatifs.
      - COLONNES : les tableaux peuvent avoir des colonnes d'exercices ANNUELS (ex: "2022", "2023", "2024") ET des colonnes SEMESTRIELLES ou trimestrielles.
        → N'extrais QUE les colonnes annuelles complètes (12 mois). Ignore les colonnes "S1", "S2", "H1" ou "semestre".
        → Compte bien TOUTES les colonnes annuelles présentes — il peut y avoir 3, 4, ou même 5 exercices dans un seul document.
        → Crée une entrée dans le tableau `years` pour CHAQUE exercice annuel trouvé.
      - Extrais UNIQUEMENT les exercices annuels COMPLETS (12 mois). Ignore les semestres, trimestres ou périodes partielles.
      - Pour les groupes avec exercice décalé (ex: avril-mars), le fiscal_year est l'année de clôture (ex: exercice 2024-2025 → fiscal_year: 2025, period_end_date: "2025-03-31").
      - Pour les P&L au format IFRS "fonction" (coût des ventes, frais commerciaux, frais admin), utilise les champs cost_of_sales, gross_margin, distribution_marketing_costs, administrative_costs. Laisse null les champs PCG (merchandise_sales, value_added, etc.) s'ils ne sont pas présents.

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

  # Passe A : extraction ciblée du compte de résultat
  def build_vision_income_prompt
    <<~PROMPT
      Tu es un expert-comptable et analyste financier.
      Les images ci-jointes contiennent des tableaux de COMPTE DE RÉSULTAT.
      Extrais toutes les données du compte de résultat pour CHAQUE exercice annuel visible.

      ## Instructions critiques
      - Retourne UNIQUEMENT un bloc JSON valide (aucune explication).
      - Utilise `null` pour toute valeur absente ou illisible.
      - Retourne les montants EXACTEMENT tels qu'écrits — sans conversion.
      - Si "En millions d'euros" ou "M€" : `"unit": 1000000` dans meta.
      - Montants négatifs = nombres négatifs.
      - Extrais TOUTES les colonnes annuelles complètes (12 mois). Ignore S1/S2/trimestres.
      - Il peut y avoir 3 à 5 exercices annuels dans un seul tableau.

      ## Correspondances IFRS — compte de résultat
      - "Chiffre d'affaires net" / "Ventes nettes" → `revenue`
      - "Coût des ventes" → `cost_of_sales`
      - "Résultat brut" / "Marge brute" → `gross_margin`
      - "Frais commerciaux et marketing" → `distribution_marketing_costs`
      - "Frais généraux et administratifs" → `administrative_costs`
      - "Résultat opérationnel courant" / "EBIT" / "Résultat d'exploitation" → `ebit`
      - "Coût de l'endettement net" → `financial_expenses`
        ⚠️ Ce montant est DÉJÀ NET (charges d'intérêts MOINS produits de trésorerie).
           Il peut être NÉGATIF pour les sociétés en trésorerie nette positive.
           Retourne-le tel quel, sans changer le signe.
      - "Impôts sur les résultats" → `income_tax`
      - "Résultat net (part du groupe)" → `net_income`
      - "Intérêts minoritaires" → `minority_interests`
      - "Dotations aux amortissements" (si présent dans l'IS) → `depreciation_amortization`

      ## Structure JSON attendue
      ```json
      {
        "company": {
          "name": "Nom légal",
          "sector": null,
          "country": "France",
          "currency": "EUR",
          "accounting_standard": "ifrs",
          "is_consolidated": true
        },
        "years": [
          {
            "meta": {
              "fiscal_year": 2021,
              "period_end_date": "2021-12-31",
              "accounting_standard": "ifrs",
              "is_consolidated": true,
              "income_format": "fonction",
              "unit": 1000000
            },
            "income_statement": {
              "revenue": null,
              "cost_of_sales": null,
              "gross_margin": null,
              "distribution_marketing_costs": null,
              "administrative_costs": null,
              "ebit": null,
              "financial_expenses": null,
              "financial_income": null,
              "income_tax": null,
              "net_income": null,
              "minority_interests": null,
              "depreciation_amortization": null,
              "personnel_expenses": null,
              "other_operating_income": null,
              "other_operating_expenses": null
            }
          }
        ]
      }
      ```
    PROMPT
  end

  # Passe B : extraction ciblée du tableau de flux et du bilan
  def build_vision_cfs_bilan_prompt
    <<~PROMPT
      Tu es un expert-comptable et analyste financier.
      Les images ci-jointes contiennent des tableaux de FLUX DE TRÉSORERIE et de BILAN.
      Extrais ces données pour CHAQUE exercice annuel visible.

      ## Instructions critiques
      - Retourne UNIQUEMENT un bloc JSON valide (aucune explication).
      - Utilise `null` pour toute valeur absente ou illisible.
      - Retourne les montants EXACTEMENT tels qu'écrits — sans conversion.
      - Si "En millions d'euros" ou "M€" : `"unit": 1000000` dans meta.
      - Montants négatifs = nombres négatifs.
      - Extrais TOUTES les colonnes annuelles complètes. Ignore S1/S2/trimestres.

      ## Tableau de flux de trésorerie — correspondances
      - "Résultat net consolidé" → `net_income` (dans cash_flow_statement)
      - "Charges sans incidence sur la trésorerie" / "Dotations nettes" → `depreciation_amortization`
      - "Capacité d'autofinancement" / "CAF" → `self_financing_capacity`
        (ligne explicite = RN + charges sans incidence, AVANT variation BFR)
      - "Variation du besoin en fonds de roulement" → `total_wcr_variation`
      - "Flux de trésorerie liés à l'exploitation" / "Flux d'exploitation" → `operating_cash_flow`
      - "Investissements nets" / "CAPEX" → `capital_expenditure` (valeur positive)
      - "Flux de trésorerie liés aux investissements" → `investing_cash_flow`
      - "Flux disponible" / "Free Cash Flow" / "FCF" → `free_cash_flow`
      - "Dividendes versés" → `dividends_paid`
      - "Endettement net en début de période" → `net_debt_opening`
      - "Endettement net en fin de période" → `net_debt_closing`

      ## Bilan — correspondances
      - "Goodwill" → `goodwill`
      - "Immobilisations incorporelles" → `intangible_assets_net`
      - "Immobilisations corporelles" → `tangible_assets_net`
      - "Actifs immobilisés nets" / "Total immobilisations" → `total_fixed_assets_net`
      - "Stocks" → `total_inventory`
      - "Créances clients" / "Clients" → `trade_receivables`
      - "Disponibilités" / "Trésorerie" → `cash_and_equivalents`
      - "Total Actif" → `total_assets`
      - "Capitaux propres (part du groupe)" → `total_equity`
      - "Intérêts minoritaires" (passif) → (balance_sheet) `minority_interests`
      - "Provisions pour risques" → `provisions_for_risks`
      - "Dettes financières long terme" → `lt_financial_debt`
      - "Dettes financières court terme" → `st_financial_debt`
      - "Fournisseurs" → `trade_payables`
      - "Total Passif" / "Total Capitaux propres et passifs" → `total_equity_and_liabilities`

      ## Structure JSON attendue
      ```json
      {
        "years": [
          {
            "meta": {
              "fiscal_year": 2021,
              "unit": 1000000
            },
            "cash_flow_statement": {
              "net_income": null,
              "depreciation_amortization": null,
              "self_financing_capacity": null,
              "total_wcr_variation": null,
              "operating_cash_flow": null,
              "capital_expenditure": null,
              "investing_cash_flow": null,
              "free_cash_flow": null,
              "dividends_paid": null,
              "net_debt_opening": null,
              "net_debt_closing": null
            },
            "balance_sheet": {
              "goodwill": null,
              "intangible_assets_net": null,
              "tangible_assets_net": null,
              "total_fixed_assets_net": null,
              "total_inventory": null,
              "trade_receivables": null,
              "cash_and_equivalents": null,
              "total_current_assets": null,
              "total_assets": null,
              "total_equity": null,
              "minority_interests": null,
              "provisions_for_risks": null,
              "lt_financial_debt": null,
              "st_financial_debt": null,
              "trade_payables": null,
              "total_equity_and_liabilities": null
            }
          }
        ]
      }
      ```
    PROMPT
  end

  # ── 4. SAUVEGARDE EN BASE ─────────────────────────────────────────────

  def save_to_database(data)
    company_attrs = data["company"] || {}
    year_entries  = data["years"]   || []

    ActiveRecord::Base.transaction do
      # Créer ou retrouver la société
      company = Company.find_or_initialize_by(name: company_attrs["name"].to_s.strip)
      company.siren               = company_attrs["siren"]               if company_attrs["siren"].present?
      company.sector              = company_attrs["sector"]              if company_attrs["sector"].present?
      company.country             = company_attrs["country"]             || "France"
      company.currency            = company_attrs["currency"]            || "EUR"
      company.accounting_standard = company_attrs["accounting_standard"] || "pcg"
      company.is_consolidated     = company_attrs["is_consolidated"]     || false
      company.save!

      # Importer chaque exercice via le service existant
      year_entries.each do |entry|
        meta = entry["meta"] || {}
        unit = (meta["unit"] || 1).to_f

        fiscal_year  = meta["fiscal_year"]&.to_i
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

  # Identifie les numéros de pages financières (1-indexés) en scorant chaque page
  # par sa densité de chiffres et la présence de mots-clés financiers.
  # Retourne les 8 meilleures pages, triées par numéro de page.
  def detect_financial_page_numbers(pages_text, total_pages)
    return [] if pages_text.empty?

    financial_kw = /chiffre.{0,10}affaires|compte.{0,10}r[ée]sultat|bilan|
                    flux.{0,10}tr[ée]sorerie|r[ée]sultat.{0,10}net|
                    capitaux.{0,10}propres|total.{0,10}actif|ebitda|
                    dettes.{0,10}financi|amortissement/xi

    scored = pages_text.each_with_index.map do |page, idx|
      next [ 0, idx + 1 ] if page.strip.length < 50
      digits      = page.scan(/\d+/).sum(&:length).to_f
      kw_hits     = page.scan(financial_kw).size
      score       = digits / (page.length + 1) * 100 + kw_hits * 8
      [ score, idx + 1 ]
    end

    top = scored.select { |score, _| score > 5 }
                .sort_by { |score, _| -score }
                .first(8)
                .map { |_, page_num| page_num }

    top.sort
  end

  def normalize_income_format(value)
    return nil if value.nil?
    # Le LLM peut renvoyer "function" (anglais) au lieu de "fonction" (valeur enum)
    { "function" => "fonction", "nature" => "nature", "fonction" => "fonction" }.fetch(value.to_s.downcase, value)
  end

  # ── MULTI-PASS HELPERS ────────────────────────────────────────────────

  # Sépare les pages cibles en deux groupes : IS vs CFS+Bilan.
  # Le score compare les mots-clés caractéristiques de chaque type.
  def classify_financial_pages(pages_text, target_pages)
    is_kw = /compte.{0,15}r[ée]sultat|r[ée]sultat.{0,15}(d.?exploitation|op[ée]rationnel|courant)|
              marge.{0,10}brute|co[uû]t.{0,10}(des.{0,5}ventes|marchandises)|
              frais.{0,10}(commerciaux|administratifs|g[ée]n[ée]raux)|
              chiffre.{0,10}d.{0,5}affaires|r[ée]sultat.{0,10}net/xi

    cfs_kw = /capacit[ée].{0,15}autofinancement|flux.{0,10}(tr[ée]sorerie|exploitation|investissement)|
               variation.{0,10}(bfr|besoin)|capitaux.{0,10}propres|
               endettement.{0,10}(net|financier)|actif.{0,10}(non.{0,5}courant|immobilis|total)|
               dettes.{0,10}financi/xi

    is_pages  = []
    cfs_pages = []

    target_pages.each do |num|
      page_text = pages_text[num - 1] || ""
      is_score  = page_text.scan(is_kw).size
      cfs_score = page_text.scan(cfs_kw).size

      if cfs_score > is_score
        cfs_pages << num
      else
        is_pages << num
      end
    end

    # Garantir au moins 1 page par passe si plusieurs pages disponibles
    if is_pages.empty? && target_pages.size > 1
      half      = [target_pages.size / 2, 1].max
      is_pages  = target_pages.first(target_pages.size - half)
      cfs_pages = target_pages.last(half)
    elsif cfs_pages.empty? && target_pages.size > 1
      half      = [target_pages.size / 2, 1].max
      cfs_pages = target_pages.last(half)
      is_pages  = target_pages.first(target_pages.size - half)
    end

    [ is_pages, cfs_pages ]
  end

  # Construit la liste des contenus image haute résolution pour une passe donnée.
  def build_hires_contents(page_numbers, tmp_dir, thumbs)
    page_numbers.map do |num|
      path = "#{tmp_dir}/hires_#{format('%03d', num)}.png"
      path = thumbs[num - 1] if !File.exist?(path) && thumbs[num - 1]
      next unless path && File.exist?(path)
      b64 = Base64.strict_encode64(File.binread(path))
      { type: "image_url", image_url: { url: "data:image/png;base64,#{b64}", detail: "high" } }
    end.compact
  end

  # Fusionne les résultats des deux passes : IS depuis data_a, CFS+Bilan depuis data_b.
  # Les deux hash sont déjà normalisés par normalize_json.
  def merge_financial_data(data_a, data_b)
    return data_a if data_b.nil?

    supp_by_year = (data_b["years"] || []).index_by { |y| y.dig("meta", "fiscal_year") }

    merged = (data_a["years"] || []).map do |b_entry|
      fy      = b_entry.dig("meta", "fiscal_year")
      s_entry = supp_by_year[fy]
      next b_entry unless s_entry

      b_entry.merge(
        "balance_sheet"       => merge_section(b_entry["balance_sheet"],       s_entry["balance_sheet"]),
        "cash_flow_statement" => merge_section(b_entry["cash_flow_statement"],  s_entry["cash_flow_statement"])
      )
    end

    # Exercices présents uniquement dans la passe B (cas rare)
    base_years = (data_a["years"] || []).map { |y| y.dig("meta", "fiscal_year") }.to_set
    supp_only  = (data_b["years"] || []).reject { |y| base_years.include?(y.dig("meta", "fiscal_year")) }

    data_a.merge("years" => merged + supp_only)
  end

  # Fusionne deux sections (hash) : garde les valeurs de base et complète avec les non-nil du supplément.
  def merge_section(base_s, supp_s)
    return base_s unless supp_s.is_a?(Hash)
    return supp_s unless base_s.is_a?(Hash)
    base_s.merge(supp_s.reject { |_, v| v.nil? })
  end

  def save_sub(report, association, attrs, unit)
    return unless attrs.is_a?(Hash)

    record = report.public_send(association) || report.public_send(:"build_#{association}")
    record.assign_attributes(scale(attrs, unit))

    # Backfill pour le compte de résultat
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
    end

    record.save!
  end

  def scale(attrs, unit)
    attrs.transform_values { |v| v.is_a?(Numeric) ? (v * unit).round(2) : v }
  end
end
