class SaleItem < ApplicationRecord
  belongs_to :sale
  belongs_to :product
  validates :quantity, numericality: { greater_than: 0 }
  validate :stock_available

  private

  def stock_available
    return unless product && quantity
    # stok tersedia = stok sekarang + qty lama (kalau update, biar tidak hitung diri sendiri)
    available = product.current_stock
    # untuk update, kembalikan qty lama dulu
    if persisted? && quantity_changed?
      old_qty = quantity_was || 0
      available += old_qty
    elsif persisted?
      return # qty tidak berubah, tidak perlu validasi
    end
    if quantity > available
      errors.add(:quantity, "melebihi stok tersedia (#{product.name}: sisa #{available}, mau jual #{quantity})")
    end
  end
end
