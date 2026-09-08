class SalesController < ApplicationController
  def index
    @sales = Sale.includes(:student).order(sale_date: :desc)
  end

  def show
    @sale = Sale.includes(:sale_items => :product, :debt_payments => :sale).find(params[:id])
  end

  def destroy
    @sale = Sale.find(params[:id])
    # Lepaskan pesanan online yang nyambung ke transaksi ini biar tidak kena foreign key
    Order.where(sale_id: @sale.id).update_all(sale_id: nil)
    @sale.destroy
    redirect_to sales_path, notice: "Transaksi dihapus"
  end
end
