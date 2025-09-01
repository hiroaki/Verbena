class EmlSource < ApplicationRecord
  has_many :mail_queues, dependent: :destroy

  validates :eml, presence: true
end
