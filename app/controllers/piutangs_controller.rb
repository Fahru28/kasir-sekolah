class PiutangsController < ApplicationController
  def index
    @piutangs = Sale.where(payment_method: "Piutang").includes(:student).order(sale_date: :desc)
  end
end
