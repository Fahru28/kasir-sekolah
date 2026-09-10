class Product < ApplicationRecord
  has_many :stock_entries, dependent: :destroy
  has_many :sale_items, dependent: :restrict_with_error
  has_many :order_items, dependent: :restrict_with_error

  validates :code, :name, presence: true
  validates :code, uniqueness: true

  # Single-query stock calculation via SQL (no N+1) - use with_stock scope to get computed column
  scope :with_stock, -> {
    left_joins(:stock_entries, :sale_items)
      .select("products.*, COALESCE(SUM(DISTINCT stock_entries.quantity),0) as _stock_in, COALESCE(SUM(DISTINCT sale_items.quantity),0) as _stock_sold")
      .group("products.id")
  }

  # Fast stock using pre-joined aggregates (avoids 2 queries per product)
  # Usage: Product.with_stock_fast or Product.select_with_stock_sql
  scope :with_stock_fast, -> {
    stock_in_sql = "(SELECT COALESCE(SUM(quantity),0) FROM stock_entries WHERE stock_entries.product_id = products.id)"
    stock_sold_sql = "(SELECT COALESCE(SUM(quantity),0) FROM sale_items WHERE sale_items.product_id = products.id)"
    select("products.*, (COALESCE(initial_stock,0) + #{stock_in_sql} - #{stock_sold_sql}) AS computed_stock")
  }

  scope :low_stock_sql, -> {
    with_stock_fast.where("COALESCE(initial_stock,0) + (SELECT COALESCE(SUM(quantity),0) FROM stock_entries WHERE stock_entries.product_id = products.id) - (SELECT COALESCE(SUM(quantity),0) FROM sale_items WHERE sale_items.product_id = products.id) <= COALESCE(min_stock,0)")
  }

  def stock_in
    stock_entries.sum(:quantity)
  end

  def stock_sold
    sale_items.sum(:quantity)
  end

  def current_stock
    # If preloaded via with_stock_fast, use computed column (0 query)
    if has_attribute?(:computed_stock) && !read_attribute(:computed_stock).nil?
      read_attribute(:computed_stock).to_i
    else
      initial_stock.to_i + stock_in - stock_sold
    end
  end

  def low_stock?
    # Use computed_stock if available (0 query), else fallback
    if has_attribute?(:computed_stock) && !read_attribute(:computed_stock).nil?
      read_attribute(:computed_stock).to_i <= min_stock.to_i
    else
      current_stock <= min_stock.to_i
    end
  end
end
