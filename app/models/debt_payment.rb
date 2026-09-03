class DebtPayment < ApplicationRecord
  belongs_to :sale
  validates :amount, numericality: { greater_than: 0 }

  after_save :update_sale_status
  after_destroy :update_sale_status

  private

  def update_sale_status
    if sale.outstanding <= 0 && sale.payment_method == "Piutang"
      sale.update_columns(status: "Lunas")
    elsif sale.outstanding > 0 && sale.payment_method == "Piutang"
      sale.update_columns(status: "Belum Lunas")
    end
  end
end
