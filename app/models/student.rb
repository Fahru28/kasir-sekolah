class Student < ApplicationRecord
  has_many :sales, dependent: :restrict_with_error

  validates :code, :name, presence: true
  validates :code, uniqueness: true

  scope :active, -> { where(active: true) }

  def debt_total
    sales.where(status: "Belum Lunas").sum { |s| s.remaining_debt }
  end
end
