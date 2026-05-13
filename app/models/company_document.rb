class CompanyDocument < ApplicationRecord
  belongs_to :company
  has_one_attached :file

  DOCUMENT_TYPES = %w[annual_report financial_data supplementary].freeze
  STATUSES       = %w[pending processing processed error].freeze

  attribute :document_type, :string, default: "annual_report"
  attribute :status,        :string, default: "pending"
  enum :document_type, DOCUMENT_TYPES.index_by(&:itself), prefix: false
  enum :status,        STATUSES.index_by(&:itself),        prefix: false

  validates :document_type, inclusion: { in: DOCUMENT_TYPES }
  validates :status,         inclusion: { in: STATUSES }

  ACCEPTED_FORMATS = %w[
    application/pdf
    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
    application/vnd.ms-excel
    text/csv
    application/vnd.openxmlformats-officedocument.wordprocessingml.document
    application/msword
    application/vnd.openxmlformats-officedocument.presentationml.presentation
    application/vnd.ms-powerpoint
  ].freeze

  HUMAN_TYPE_LABELS = {
    "annual_report"  => "Rapport annuel",
    "financial_data" => "Données financières",
    "supplementary"  => "Document complémentaire"
  }.freeze

  def human_type  = HUMAN_TYPE_LABELS.fetch(document_type, document_type)
  def processed?  = status == "processed"
  def pending?    = status == "pending"

  def filename
    original_filename.presence || file.filename.to_s
  end

  def format_label
    return "—" unless file.attached?
    case file.content_type
    when /pdf/                  then "PDF"
    when /spreadsheet|excel|csv/ then "Excel/CSV"
    when /wordprocessing|msword/ then "Word"
    when /presentation|powerpoint/ then "PowerPoint"
    else file.content_type.split("/").last.upcase
    end
  end
end
