class Order < ApplicationRecord
  has_many :order_items, dependent: :destroy
  accepts_nested_attributes_for :order_items, allow_destroy: true

  validates :customer_name, presence: true
  validates :status, inclusion: { in: %w[Menunggu Siap_Diambil Selesai Dibatalkan] }

  before_validation :set_defaults

  scope :pending, -> { where(status: "Menunggu") }
  scope :recent, -> { order(created_at: :desc) }

  def status_label
    status.gsub("_", " ")
  end

  def recalc_total!
    update!(total_amount: order_items.sum(:subtotal))
  end

  private

  def set_defaults
    self.status ||= "Menunggu"
    self.total_amount ||= 0
  end
end
