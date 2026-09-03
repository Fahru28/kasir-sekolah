class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :product

  validates :quantity, numericality: { greater_than: 0 }
  validates :price, presence: true

  before_validation :set_price_and_subtotal

  private

  def set_price_and_subtotal
    self.price ||= product&.selling_price.to_i
    self.subtotal = quantity.to_i * price.to_i
  end
end
