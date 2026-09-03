class SalesController < ApplicationController
  def index
    @sales = Sale.includes(:student).order(sale_date: :desc)
  end

  def show
    @sale = Sale.includes(:sale_items => :product, :debt_payments => :sale).find(params[:id])
  end

  def destroy
    @sale = Sale.find(params[:id])
    @sale.destroy
    redirect_to sales_path, notice: "Transaksi dihapus"
  end
end
