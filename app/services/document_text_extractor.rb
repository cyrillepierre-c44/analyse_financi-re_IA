# Extrait le texte brut d'un CompanyDocument selon son format.
# Retourne une String (potentiellement longue).
#
# PDF  → pdf-reader pour les pages texte, GPT-4o Vision pour les pages image
# XLSX/XLS/CSV → roo
# DOCX/DOC → décompression XML interne
# PPTX/PPT → GPT-4o Vision (slides converties en images via mini_magick)
#
class DocumentTextExtractor
  MAX_VISION_PAGES = 20   # limite pour ne pas exploser le contexte

  def initialize(company_document)
    @doc  = company_document
    @file = company_document.file
  end

  def extract
    raise "Fichier non attaché" unless @file.attached?

    content_type = @file.content_type.to_s

    case content_type
    when /pdf/
      extract_pdf
    when /spreadsheet|excel|\.xlsx|\.xls/, /csv/
      extract_spreadsheet
    when /wordprocessing|msword|\.docx|\.doc/
      extract_word
    when /presentation|powerpoint|\.pptx|\.ppt/
      extract_presentation_via_vision
    else
      raise "Format non supporté : #{content_type}"
    end
  end

  private

  # ── PDF ──────────────────────────────────────────────────────────────────────
  def extract_pdf
    with_tempfile do |path|
      reader    = PDF::Reader.new(path)
      pages     = reader.pages
      text_parts = []

      pages.each_with_index do |page, idx|
        text = page.text.strip
        if text.length > 50
          text_parts << "=== Page #{idx + 1} ===\n#{text}"
        elsif idx < MAX_VISION_PAGES
          # Page pauvre en texte → Vision
          image_text = vision_page_from_pdf(path, idx + 1)
          text_parts << "=== Page #{idx + 1} [Vision] ===\n#{image_text}" if image_text.present?
        end
      end

      text_parts.join("\n\n")
    end
  end

  # ── EXCEL / CSV ───────────────────────────────────────────────────────────────
  def extract_spreadsheet
    with_tempfile do |path|
      wb = Roo::Spreadsheet.open(path)
      parts = []

      wb.sheets.each do |sheet_name|
        ws    = wb.sheet(sheet_name)
        rows  = ws.to_a.reject { |r| r.all?(&:nil?) }
        next if rows.empty?

        parts << "=== Feuille : #{sheet_name} ===\n" +
                 rows.map { |r| r.map { |c| c.to_s.strip }.join("\t") }.join("\n")
      end

      parts.join("\n\n")
    end
  end

  # ── WORD (.docx) ─────────────────────────────────────────────────────────────
  # Un .docx est un zip. On extrait word/document.xml et on supprime les balises.
  def extract_word
    with_tempfile do |path|
      require "zip"

      xml_content = Zip::File.open(path) do |zip|
        entry = zip.find_entry("word/document.xml")
        raise "document.xml introuvable dans le DOCX" unless entry
        entry.get_input_stream.read
      end

      # Suppression des balises XML + nettoyage
      xml_content.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
    end
  rescue LoadError
    raise "La gem 'rubyzip' est requise pour lire les fichiers Word (.docx). Ajoutez-la dans le Gemfile."
  end

  # ── POWERPOINT via Vision ─────────────────────────────────────────────────────
  def extract_presentation_via_vision
    with_tempfile do |path|
      # Convertir chaque slide en image via LibreOffice + ImageMagick
      # Si LibreOffice absent, on tente directement avec ImageMagick (PDF intermédiaire)
      Dir.mktmpdir do |tmpdir|
        images = convert_to_images(path, tmpdir)
        if images.empty?
          raise "Impossible de convertir la présentation en images (LibreOffice/ImageMagick manquant ?)"
        end

        parts = images.first(MAX_VISION_PAGES).each_with_index.map do |img_path, idx|
          text = vision_from_image_path(img_path)
          "=== Slide #{idx + 1} ===\n#{text}"
        end

        parts.join("\n\n")
      end
    end
  end

  # ── HELPERS ───────────────────────────────────────────────────────────────────

  # Télécharge le blob dans un fichier temporaire et yield le chemin
  def with_tempfile
    ext = File.extname(@file.filename.to_s)
    Tempfile.create(["doc_extract_", ext]) do |tmp|
      tmp.binmode
      @file.download { |chunk| tmp.write(chunk) }
      tmp.flush
      yield tmp.path
    end
  end

  # Convertit une page PDF en image et l'envoie à GPT-4o Vision
  def vision_page_from_pdf(pdf_path, page_number)
    Dir.mktmpdir do |tmpdir|
      img_path = File.join(tmpdir, "page_#{page_number}.png")
      # poppler-utils : pdftoppm -r 150 -f N -l N
      result = system("pdftoppm -r 150 -f #{page_number} -l #{page_number} -png \"#{pdf_path}\" \"#{tmpdir}/page\"")
      # pdftoppm génère page-000001.png etc.
      candidates = Dir["#{tmpdir}/page*.png"].sort
      return nil if candidates.empty?

      vision_from_image_path(candidates.first)
    end
  end

  # Convertit un fichier (PDF/PPT) en liste d'images PNG
  def convert_to_images(file_path, output_dir)
    ext = File.extname(file_path).downcase

    if ext == ".pdf"
      system("pdftoppm -r 120 -png \"#{file_path}\" \"#{output_dir}/slide\"")
    else
      # LibreOffice → PDF → images
      system("libreoffice --headless --convert-to pdf --outdir \"#{output_dir}\" \"#{file_path}\" 2>/dev/null")
      pdf_file = Dir["#{output_dir}/*.pdf"].first
      if pdf_file
        system("pdftoppm -r 120 -png \"#{pdf_file}\" \"#{output_dir}/slide\"")
      end
    end

    Dir["#{output_dir}/slide*.png"].sort
  end

  # Envoie une image à GPT-4o Vision et retourne le texte extrait
  def vision_from_image_path(image_path)
    image_data = Base64.strict_encode64(File.binread(image_path))
    mime_type  = "image/png"

    response = llm_vision_request([
      {
        type: "image_url",
        image_url: { url: "data:#{mime_type};base64,#{image_data}" }
      },
      {
        type: "text",
        text: "Extrait tout le texte et les données chiffrées présents dans cette image. " \
              "Conserve la structure (tableaux, titres, puces). Réponds uniquement avec le contenu extrait, sans commentaire."
      }
    ])

    response
  end

  # Appel à l'API GPT-4o via GitHub Models (même endpoint que le reste de l'app)
  def llm_vision_request(content_parts)
    require "net/http"
    require "json"

    uri  = URI(ENV.fetch("GITHUB_MODELS_URL", "https://models.inference.ai.azure.com") + "/chat/completions")
    key  = ENV.fetch("GITHUB_KEY")

    body = {
      model:       ENV.fetch("GITHUB_MODEL", "gpt-4o"),
      messages:    [ { role: "user", content: content_parts } ],
      max_tokens:  2000,
      temperature: 0
    }

    req             = Net::HTTP::Post.new(uri)
    req["Content-Type"]  = "application/json"
    req["Authorization"] = "Bearer #{key}"
    req.body             = body.to_json

    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
    parsed = JSON.parse(res.body)

    parsed.dig("choices", 0, "message", "content") || ""
  rescue => e
    Rails.logger.error "[Vision] Erreur GPT-4o : #{e.message}"
    ""
  end
end
