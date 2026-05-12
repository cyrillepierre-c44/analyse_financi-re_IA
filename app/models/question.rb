class Question < ApplicationRecord
  has_many :company_answers, dependent: :destroy

  validates :text, :position, :answer_type, presence: true
  validates :answer_type, inclusion: { in: %w[single multiple numerical] }
  validates :position, uniqueness: true

  default_scope { order(:position) }

  def multiple?  = answer_type == "multiple"
  def numerical? = answer_type == "numerical"
end
