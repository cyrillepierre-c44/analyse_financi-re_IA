class Company < ApplicationRecord
  has_many :financial_reports, dependent: :destroy

  enum :accounting_standard, { pcg: 0, ifrs: 1 }

  validates :name, presence: true
  validates :currency, presence: true
  validates :country, presence: true
end
