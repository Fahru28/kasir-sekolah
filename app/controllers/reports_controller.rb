class ReportsController < ApplicationController
  def daily
    @from = params[:from].present? ? Date.parse(params[:from]) : Date.current.beginning_of_month
    @to = params[:to].present? ? Date.parse(params[:to]) : Date.current
    @from, @to = @to, @from if @from > @to

    @sales = Sale.includes(:student, :sale_items).where(sale_date: @from..@to).order(sale_date: :desc, created_at: :desc)

    # Per-day aggregation
    @per_day = @sales.group_by(&:sale_date).sort.reverse.to_h
    @total_omzet = @sales.sum(:total_amount)
    @total_profit = @sales.sum(:profit)
    @total_trx = @sales.size
    @total_items = @sales.sum(:total_items)
    @tunai = @sales.select { |s| s.payment_method == "Tunai" }.sum(&:total_amount)
    @piutang = @sales.select { |s| s.payment_method == "Piutang" }.sum(&:total_amount)
    @transfer = @sales.select { |s| %w[Transfer QRIS].include?(s.payment_method) }.sum(&:total_amount)

    # Top products in range
    @top_products = SaleItem.joins(:sale).where(sales: { sale_date: @from..@to })
                            .joins(:product).group("products.name").sum(:quantity)
                            .sort_by { |_, q| -q }.first(5)
  rescue ArgumentError
    redirect_to daily_reports_path, alert: "Format tanggal tidak valid"
  end
end
