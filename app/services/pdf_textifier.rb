require "base64"
require "shellwords"
require "fileutils"

# Convertit un PDF en texte structuré lisible par une IA, page par page.
# Chaque page est rendue en PNG (Ghostscript) puis envoyée à GPT-4o Vision.
# Les tableaux deviennent du Markdown, les graphiques deviennent des tableaux de données.
#
# Usage :
#   text = PdfTextifier.call("/tmp/file.pdf")
#   # => String avec marqueurs "=== PAGE N ===" entre chaque page
#
class PdfTextifier
  MODEL = "gpt-4o"

  def self.call(pdf_path)
    new(pdf_path).call
  end

  def initialize(pdf_path)
    @pdf_path = pdf_path
  end

  def call
    tmp_dir = Rails.root.join("tmp", "textify_#{SecureRandom.hex(6)}")
    FileUtils.mkdir_p(tmp_dir)

    begin
      convert_to_png(tmp_dir)
      pngs = Dir["#{tmp_dir}/page_*.png"].sort
      raise "Ghostscript n'a produit aucune image" if pngs.empty?

      Rails.logger.info "[PdfTextifier] #{pngs.size} pages à textifier"

      pages_text = pngs.each_with_index.map do |path, idx|
        page_num = idx + 1
        Rails.logger.info "[PdfTextifier] Page #{page_num}/#{pngs.size}..."
        text = textify_page(path, page_num, pngs.size)
        text.present? ? "=== PAGE #{page_num} ===\n#{text}" : nil
      end.compact

      result = pages_text.join("\n\n")
      Rails.logger.info "[PdfTextifier] Textification terminée : #{result.length} chars"
      result
    ensure
      FileUtils.rm_rf(tmp_dir)
    end
  end

  private

  def convert_to_png(tmp_dir)
    system(
      "gs -dNOPAUSE -dBATCH -sDEVICE=png16m -r150 " \
      "-sOutputFile=#{tmp_dir}/page_%03d.png #{Shellwords.escape(@pdf_path)} " \
      ">/dev/null 2>&1"
    )
  end

  def textify_page(png_path, page_num, total_pages)
    b64      = Base64.strict_encode64(File.binread(png_path))
    attempts = 0

    begin
      attempts += 1
      raw = call_api(messages: [{
        role: "user",
        content: [
          { type: "text", text: build_prompt(page_num, total_pages) },
          { type: "image_url", image_url: { url: "data:image/png;base64,#{b64}", detail: "high" } }
        ]
      }])
      raw.strip == "PAGE_VIDE" ? "" : raw.strip
    rescue RuntimeError => e
      if attempts < 3 && e.message.include?("429")
        wait = e.message.match(/wait (\d+) second/)&.[](1)&.to_i || 120
        Rails.logger.info "[PdfTextifier] Rate limit page #{page_num}, attente #{wait + 5}s..."
        sleep(wait + 5)
        retry
      end
      Rails.logger.warn "[PdfTextifier] Page #{page_num} ignorée : #{e.message}"
      ""
    end
  end

  def build_prompt(page_num, total_pages)
    <<~PROMPT
      Page #{page_num}/#{total_pages} d'un document financier.

      Retranscris FIDÈLEMENT tout le contenu de cette page. Aucune interprétation, aucun résumé.

      Règles :
      - Texte ordinaire → copier mot pour mot, conserver titres, listes, numérotation
      - Tableau (texte natif ou capture d'écran) → format Markdown avec | comme séparateur de colonnes
      - Graphique / courbe → tableau de données extrait visuellement :
        | Période | Série 1 | Série 2 | ... | (écrire ~valeur si estimation visuelle)
      - Questions numérotées → copier telles quelles avec leurs numéros
      - Légendes, notes de bas de page, unités → conserver
      - Numéro de page seul ou en-tête répétitif → ignorer
      - Page vide ou purement décorative (logo seul, fond coloré sans texte) → répondre uniquement : PAGE_VIDE
    PROMPT
  end

  def call_api(messages:)
    api_key = ENV["GITHUB_KEY"].presence or raise "GITHUB_KEY absent"

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
        messages:    messages,
        temperature: 0,
        max_tokens:  2000
      }.to_json
    end

    unless response.status == 200
      err = response.body.dig("error", "message") || response.body.inspect
      raise "Erreur API (#{response.status}) : #{err}"
    end

    response.body.dig("choices", 0, "message", "content").to_s
  end
end
