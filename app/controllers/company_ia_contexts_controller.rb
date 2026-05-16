class CompanyIaContextsController < ApplicationController
  def update
    @company = Company.find(params[:company_id])
    @company.update!(ia_context: params.dig(:company, :ia_context))
    redirect_to @company, notice: "Contexte IA enregistré."
  end

  def fill_gaps
    @company = Company.find(params[:company_id])
    answers  = params[:gap_answers].to_h.reject { |_, v| v.strip.blank? }
    return redirect_to @company, alert: "Aucune réponse saisie." if answers.empty?

    block = answers.map { |gap, answer| "- #{gap} : #{answer.strip}" }.join("\n")
    prefix = "## Données complémentaires (saisie manuelle)\n#{block}\n\n"
    existing = @company.ia_context.to_s.sub(/\A## Données complémentaires.*?\n\n/m, "")
    @company.update!(ia_context: prefix + existing)

    redirect_to @company, notice: "#{answers.size} réponse(s) enregistrée(s) dans le contexte."
  end
end
