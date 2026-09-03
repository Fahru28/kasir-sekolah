class DashboardController < ApplicationController
  def index
    today = Date.current
    begin
      sales_today = Sale.where(sale_date: today)
      @total_sales_today = sales_today.sum(:total_amount) || 0
      @tx_count_today = sales_today.count
      @profit_today = sales_today.sum(:profit) || 0
      @total_piutang = Sale.where(payment_method: "Piutang").sum { |s| s.outstanding rescue 0 } || 0
      @low_stock = Product.all.select { |p| p.low_stock? rescue false } || []
      @recent_sales = Sale.includes(:student).order(sale_date: :desc).limit(5)
      @pending_orders = Order.includes(order_items: :product).where(status: "Menunggu").order(created_at: :desc).limit(5)
      @pending_count = Order.where(status: "Menunggu").count
    rescue => e
      Rails.logger.error("Dashboard error: #{e.message}")
      @total_sales_today = 0
      @tx_count_today = 0
      @profit_today = 0
      @total_piutang = 0
      @low_stock = []
      @recent_sales = []
      @pending_orders = []
      @pending_count = 0
    end
  end
end
