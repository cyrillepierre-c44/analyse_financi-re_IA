class CompanyAnswer < ApplicationRecord
  belongs_to :company
  belongs_to :question

  validates :company, :question, presence: true
end
