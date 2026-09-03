class Order < ApplicationRecord
  belongs_to :sale, optional: true
  has_many :order_items, dependent: :destroy
  accepts_nested_attributes_for :order_items, allow_destroy: true

  validates :customer_name, presence: true
  validates :status, inclusion: { in: %w[Menunggu Siap_Diambil Selesai Dibatalkan] }

  before_validation :set_defaults
  after_update :convert_to_sale_if_done, if: :saved_change_to_status?

  scope :pending, -> { where(status: "Menunggu") }
  scope :recent, -> { order(created_at: :desc) }

  def status_label
    status.gsub("_", " ")
  end

  def recalc_total!
    update!(total_amount: order_items.sum(:subtotal))
  end

  # Pas status jadi Selesai, otomatis bikin transaksi Sale supaya masuk Dashboard & Riwayat
  def convert_to_sale_if_done
    return unless status == "Selesai" && sale_id.nil?

    # Cari / bikin student dummy untuk pesanan online
    student = Student.find_or_create_by!(code: "ONLINE") do |s|
      s.name = customer_name
      s.nis = "0"
      s.class_name = customer_class.presence || "-"
      s.guardian_name = customer_name
      s.phone = customer_phone
      s.address = "-"
      s.active = true
    end
    # kalau sudah ada ONLINE tapi nama beda, pakai yang ada saja
    student = Student.find_by(code: "ONLINE")

    sale = Sale.create!(
      number: "ORD-#{id}-#{Time.current.strftime('%Y%m%d')}",
      sale_date: Date.current,
      student: student,
      total_items: order_items.sum(:quantity),
      total_amount: total_amount.to_i,
      payment_method: "Tunai",
      amount_paid: total_amount.to_i,
      status: "Lunas",
      profit: order_items.sum { |oi| (oi.price.to_i - (oi.product.cost_price.to_i)) * oi.quantity.to_i }
    )

    order_items.each do |oi|
      SaleItem.create!(
        sale: sale,
        product: oi.product,
        quantity: oi.quantity,
        selling_price: oi.price,
        cost_price: oi.product.cost_price.to_i,
        subtotal: oi.subtotal,
        profit: (oi.price.to_i - oi.product.cost_price.to_i) * oi.quantity.to_i
      )
    end

    update_column(:sale_id, sale.id)
  end

  private

  def set_defaults
    self.status ||= "Menunggu"
    self.total_amount ||= 0
  end
end
