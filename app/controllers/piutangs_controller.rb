class PiutangsController < ApplicationController
  def index
    # Preload debt_payments + compute outstanding in SQL (no N+1)
    paid_sql = "COALESCE((SELECT SUM(amount) FROM debt_payments WHERE debt_payments.sale_id = sales.id),0)"
    @piutangs = Sale.where(payment_method: "Piutang")
                    .includes(:student, :debt_payments)
                    .select("sales.*, (sales.total_amount - #{paid_sql}) AS computed_outstanding, #{paid_sql} AS computed_paid")
                    .order(sale_date: :desc)
    @total_outstanding = @piutangs.sum { |s| s.read_attribute(:computed_outstanding).to_i } rescue 0
    @count_outstanding = @piutangs.count { |s| s.read_attribute(:computed_outstanding).to_i > 0 } rescue 0
  end
end
