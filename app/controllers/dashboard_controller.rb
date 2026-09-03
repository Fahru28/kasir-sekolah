class DashboardController < ApplicationController
  def index
    today = Date.current
    sales_today = Sale.where(sale_date: today)
    @total_sales_today = sales_today.sum(:total_amount)
    @tx_count_today = sales_today.count
    @profit_today = sales_today.sum(:profit)
    @total_piutang = Sale.where(payment_method: "Piutang").where.not(status: "Lunas").sum(:total_amount) - DebtPayment.joins(:sale).where(sales: { payment_method: "Piutang" }).sum(:amount)
    # outstanding piutang calc
    @total_piutang = Sale.where(payment_method: "Piutang").sum { |s| s.outstanding }
    @low_stock = Product.all.select(&:low_stock?)
    @recent_sales = Sale.includes(:student).order(sale_date: :desc).limit(5)
  end
end
