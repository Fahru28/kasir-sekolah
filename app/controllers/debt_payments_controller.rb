class DebtPaymentsController < ApplicationController
  def create
    @sale = Sale.find(params[:sale_id])
    @payment = @sale.debt_payments.build(payment_params)
    @payment.payment_date ||= Date.current
    if @payment.save
      redirect_to sale_path(@sale), notice: "Pembayaran dicatat"
    else
      redirect_to sale_path(@sale), alert: @payment.errors.full_messages.join(", ")
    end
  end

  def destroy
    @payment = DebtPayment.find(params[:id])
    sale = @payment.sale
    @payment.destroy
    redirect_to sale_path(sale), notice: "Pembayaran dihapus"
  end

  private

  def payment_params
    params.require(:debt_payment).permit(:payment_date, :amount, :note)
  end
end
