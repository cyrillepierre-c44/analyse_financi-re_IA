# Recherche web via l'API Tavily.
# Retourne un tableau de { title:, url:, content: }.
#
# Usage :
#   results = WebSearchService.new.search("Laurent-Perrier résultats annuels 2024")
#
class WebSearchService
  TAVILY_URL   = "https://api.tavily.com/search"
  MAX_RESULTS  = 5

  class NotConfiguredError < StandardError; end

  def search(query, max_results: MAX_RESULTS)
    key = ENV["TAVILY_API_KEY"]
    raise NotConfiguredError, "TAVILY_API_KEY manquant dans .env" if key.blank?

    require "net/http"
    require "json"

    uri  = URI(TAVILY_URL)
    body = {
      api_key:             key,
      query:               query,
      search_depth:        "advanced",
      include_answer:      false,
      include_raw_content: false,
      max_results:         max_results
    }

    req             = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req.body            = body.to_json

    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 15) do |h|
      h.request(req)
    end

    raise "Tavily API error #{res.code}" unless res.is_a?(Net::HTTPSuccess)

    parsed  = JSON.parse(res.body)
    results = parsed["results"] || []

    results.map do |r|
      {
        title:   r["title"].to_s,
        url:     r["url"].to_s,
        content: r["content"].to_s.truncate(1500)
      }
    end
  rescue NotConfiguredError => e
    Rails.logger.warn "[WebSearch] #{e.message}"
    []
  rescue => e
    Rails.logger.error "[WebSearch] Erreur : #{e.message}"
    []
  end
end
