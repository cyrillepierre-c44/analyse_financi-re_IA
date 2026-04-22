module ApplicationHelper
  # Transforme le markdown simple retourné par le LLM en HTML lisible
  def render_analysis(text)
    return "" if text.blank?
    html = text
      .gsub(/\*\*(.+?)\*\*/, '<strong>\1</strong>')          # **gras**
      .gsub(/^#+\s+(.+)$/, '<h3 class="font-semibold text-gray-900 mt-5 mb-2 text-base">\1</h3>')
      .split(/\n{2,}/)
      .map do |para|
        para = para.strip
        next "" if para.empty?
        next para if para.start_with?("<h3")
        "<p class=\"mb-3\">#{para.gsub("\n", " ")}</p>"
      end
      .join
    html.html_safe
  end
  # Formate un montant en euros : 1 234 567 €
  def euros(amount, unit: "€")
    return "—" if amount.nil?
    formatted = number_with_delimiter(amount.round(0).to_i, delimiter: "\u202f")
    "#{formatted}\u00a0#{unit}"
  end

  # Formate un pourcentage : 23,4 %
  def pct(ratio, decimals: 1)
    return "—" if ratio.nil?
    "#{number_with_precision(ratio * 100, precision: decimals, delimiter: "\u202f", separator: ",")}#{"\u00a0"}%"
  end

  # Formate un ratio simple (ex : 1,34×)
  def ratio(value, decimals: 2, suffix: "×")
    return "—" if value.nil?
    "#{number_with_precision(value, precision: decimals, separator: ",")}#{suffix}"
  end

  # Badge coloré selon valeur positive/négative/neutre
  def trend_class(value, positive_is_good: true)
    return "text-gray-400" if value.nil? || value.zero?
    good = positive_is_good ? value.positive? : value.negative?
    good ? "text-emerald-600 font-semibold" : "text-rose-600 font-semibold"
  end

  # Flèche de tendance N vs N-1
  def delta_tag(current, previous)
    return "" if current.nil? || previous.nil? || previous.zero?
    delta = (current - previous) / previous.abs * 100
    sign  = delta >= 0 ? "▲" : "▼"
    color = delta >= 0 ? "text-emerald-600" : "text-rose-600"
    content_tag(:span, "#{sign} #{number_with_precision(delta.abs, precision: 1)}%",
                class: "text-xs #{color} ml-1")
  end
end
