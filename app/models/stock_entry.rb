class StockEntry < ApplicationRecord
  belongs_to :product
  validates :quantity, numericality: { other_than: 0 }
  validate :quantity_not_zero

  private

  def quantity_not_zero
    errors.add(:quantity, "tidak boleh 0") if quantity == 0
  end
end
