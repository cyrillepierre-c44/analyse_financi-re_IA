require "faraday"
require "json"
require "pdf/reader"

# Extrait les questions de diagnostic financier depuis les documents d'une société.
# Sources (par ordre de priorité) :
#   1. CompanyDocuments Active Storage attachés à la société
#   2. Fichier PDF source identifié via financial_reports.source_file (cherché dans docs/)
# Ne s'exécute que si la société n'a pas encore de questions.
#
# Usage :
#   QuestionExtractionService.call(company)
#
class QuestionExtractionService
  MODEL    = "gpt-4o"
  API_BASE = "https://models.inference.ai.azure.com"
  MAX_TEXT_CHARS = 7_000  # conservative pour rester sous la limite 8k tokens

  def self.call(company)
    new(company).call
  end

  def initialize(company)
    @company = company
  end

  def call
    return if @company.questions.any?

    full_text = text_from_documents || text_from_source_file
    return if full_text.blank?

    # Localise la section questions (pattern "1." ou "Q1" en début de ligne)
    # puis prend une fenêtre de 14k chars à partir de là
    text_chunk = extract_questions_section(full_text)

    raw_json = ask_llm(text_chunk)
    data     = JSON.parse(raw_json)
    questions_data = data["questions"] || []
    return if questions_data.empty?

    saved = save_questions(questions_data)
    Rails.logger.info "[QuestionExtractionService] #{@company.name} : #{saved} questions extraites."
    saved
  rescue => e
    Rails.logger.error "[QuestionExtractionService] #{@company.name} : #{e.message}"
    0
  end

  private

  # Détecte le début des questions numérotées et retourne une fenêtre de 14k chars.
  # Fallback : début du texte (documents courts ou questions en tête).
  def extract_questions_section(text)
    window = MAX_TEXT_CHARS * 2   # ~14k chars ≈ 3 500 tokens

    # Cherche "1." ou "Q1." en début de ligne (souplesse sur les espaces)
    match = text.match(/^[ \t]{0,15}(?:[Qq]\s*)?1[\.\)]\s+\S/m)
    if match
      start = [0, match.begin(0) - 100].max
      text[start, window]
    else
      text[0, window]
    end
  end

  def text_from_documents
    docs = @company.company_documents.order(:created_at)
    return nil if docs.empty?
    texts = docs.filter_map { |doc| DocumentTextExtractor.new(doc).extract rescue nil }
    texts.join("\n\n").presence
  end

  # Fallback : lit le PDF source stocké dans docs/ (le même que celui importé via CompanyPdfImporter)
  def text_from_source_file
    source_name = @company.financial_reports.order(:fiscal_year).first&.source_file
    return nil if source_name.blank?

    candidates = [
      Rails.root.join("docs", source_name),
      Rails.root.join("tmp",  source_name),
      Rails.root.join(source_name)
    ]
    path = candidates.find { |p| File.exist?(p) }
    return nil unless path

    pages = PDF::Reader.new(path.to_s).pages
    pages.map(&:text).join("\n\n")
  rescue => e
    Rails.logger.warn "[QuestionExtractionService] source_file '#{source_name}' illisible : #{e.message}"
    nil
  end

  def ask_llm(text)
    api_key = ENV["GITHUB_KEY"].presence or raise "GITHUB_KEY absent"

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
        model:           MODEL,
        messages:        [
          { role: "system", content: system_prompt },
          { role: "user",   content: "Document :\n\n#{text}" }
        ],
        temperature:     0.1,
        max_tokens:      4096,
        response_format: { type: "json_object" }
      }.to_json
    end

    unless response.status == 200
      err = response.body.dig("error", "message") || response.body.inspect
      raise "Erreur API (#{response.status}) : #{err}"
    end

    response.body.dig("choices", 0, "message", "content").to_s.strip
  end

  def system_prompt
    <<~PROMPT
      Tu es un assistant spécialisé dans l'extraction de questions de cas pratiques d'analyse financière.

      Lis le document fourni et extrais TOUTES les questions numérotées (Q1, Q2, Q3… ou 1., 2., 3…).
      Pour chaque question, détermine :
      - "position" : numéro de la question (entier)
      - "text" : texte complet de la question
      - "answer_type" : "numerical" si la question demande un calcul ou une valeur chiffrée,
                        "multiple" si plusieurs réponses sont possibles parmi les options,
                        "single" si une seule réponse est attendue parmi les options
      - "options" : tableau des options proposées (tableau vide si answer_type = "numerical")

      Règles :
      - Extrais UNIQUEMENT les questions, pas les réponses ni le texte analytique.
      - Pour les questions numériques, les options sont généralement absentes (tableau vide).
      - Pour les QCM, inclus toutes les options proposées dans le document.
      - Préserve le texte exact des questions et options (sans reformulation).
      - Si tu ne trouves pas de questions numérotées, retourne {"questions": []}.

      Réponds UNIQUEMENT en JSON valide :
      {
        "questions": [
          {
            "position": 1,
            "text": "Texte de la question...",
            "answer_type": "single",
            "options": ["Option A", "Option B", "Option C"]
          }
        ]
      }
    PROMPT
  end

  def save_questions(questions_data)
    count = 0
    ApplicationRecord.transaction do
      questions_data.each do |qdata|
        position = qdata["position"].to_i
        next if position <= 0

        q = @company.questions.find_or_initialize_by(position: position)
        q.assign_attributes(
          text:        qdata["text"].to_s.strip,
          answer_type: qdata["answer_type"].presence_in(%w[single multiple numerical]) || "single",
          options:     Array(qdata["options"]).map(&:to_s)
        )
        q.save!
        count += 1
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn "[QuestionExtractionService] Q#{position} ignorée : #{e.message}"
      end
    end
    count
  end
end
