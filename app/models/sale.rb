class Sale < ApplicationRecord
  belongs_to :student
  has_many :sale_items, dependent: :destroy
  has_many :debt_payments, dependent: :destroy
  accepts_nested_attributes_for :sale_items, allow_destroy: true

  validates :number, presence: true, uniqueness: true

  def total_paid
    debt_payments.sum(:amount).to_i + (amount_paid.to_i) # amount_paid for non-credit initial; for Piutang it starts 0
  end

  def remaining_debt
    return 0 unless status == "Belum Lunas" || payment_method == "Piutang"
    total_amount.to_i - debt_payments.sum(:amount).to_i - (payment_method == "Piutang" ? 0 : 0)
  end

  # For display: if Piutang, debt = total - payments; if cash, debt 0
  def outstanding
    if payment_method == "Piutang"
      total_amount.to_i - debt_payments.sum(:amount).to_i
    else
      0
    end
  end

  def fully_paid?
    outstanding <= 0
  end
end
