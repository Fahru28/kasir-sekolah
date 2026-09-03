class KasirController < ApplicationController
  def index
    @students = Student.order(:name)
    @products = Product.order(:name)
    @cart = session[:kasir_cart] || []
  end

  def add_item
    session[:kasir_cart] ||= []
    prod = Product.find(params[:product_id])
    qty = params[:qty].to_i
    qty = 1 if qty <= 0
    existing = session[:kasir_cart].find { |i| i["product_id"] == prod.id }
    if existing
      existing["qty"] += qty
    else
      session[:kasir_cart] << { "product_id" => prod.id, "code" => prod.code, "name" => prod.name, "price" => prod.selling_price, "cost" => prod.cost_price, "qty" => qty }
    end
    redirect_to kasir_path
  end

  def remove_item
    session[:kasir_cart] ||= []
    session[:kasir_cart].reject! { |i| i["product_id"] == params[:product_id].to_i }
    redirect_to kasir_path
  end

  def clear_cart
    session[:kasir_cart] = []
    redirect_to kasir_path
  end

  def checkout
    cart = session[:kasir_cart] || []
    if cart.empty?
      redirect_to kasir_path, alert: "Keranjang kosong!" and return
    end
    student = Student.find(params[:student_id])
    payment_method = params[:payment_method]
    amount_paid = params[:amount_paid].to_i

    total = cart.sum { |i| i["price"].to_i * i["qty"].to_i }
    profit = cart.sum { |i| (i["price"].to_i - i["cost"].to_i) * i["qty"].to_i }
    total_items = cart.sum { |i| i["qty"].to_i }

    if payment_method == "Tunai" && amount_paid < total
      redirect_to kasir_path, alert: "Nominal bayar kurang! Total Rp#{total}" and return
    end

    number = "TRX-#{Date.current.strftime('%Y%m%d')}-#{Sale.count + 1 + rand(100)}"
    # ensure unique
    number = "TRX-#{Time.current.strftime('%Y%m%d%H%M%S')}-#{rand(999)}" if Sale.exists?(number: number)

    status = payment_method == "Piutang" ? "Belum Lunas" : "Lunas"

    sale = Sale.create!(
      number: number,
      sale_date: Date.current,
      student: student,
      total_items: total_items,
      total_amount: total,
      payment_method: payment_method,
      amount_paid: payment_method == "Piutang" ? 0 : amount_paid,
      status: status,
      profit: profit
    )
    cart.each do |i|
      SaleItem.create!(
        sale: sale, product_id: i["product_id"], quantity: i["qty"],
        selling_price: i["price"], cost_price: i["cost"],
        subtotal: i["price"].to_i * i["qty"].to_i,
        profit: (i["price"].to_i - i["cost"].to_i) * i["qty"].to_i
      )
    end
    session[:kasir_cart] = []
    redirect_to sale_path(sale), notice: "Transaksi #{sale.number} berhasil!"
  end
end
