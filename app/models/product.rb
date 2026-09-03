class Product < ApplicationRecord
  has_many :stock_entries, dependent: :destroy
  has_many :sale_items, dependent: :restrict_with_error

  validates :code, :name, presence: true
  validates :code, uniqueness: true

  def stock_in
    stock_entries.sum(:quantity)
  end

  def stock_sold
    sale_items.sum(:quantity)
  end

  def current_stock
    initial_stock.to_i + stock_in - stock_sold
  end

  def low_stock?
    current_stock <= min_stock.to_i
  end
end
