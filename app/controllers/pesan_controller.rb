class PesanController < ApplicationController
  skip_before_action :authenticate_user!, raise: false

  before_action :load_products

  def index
    @cart = session[:pesan_cart] || {}
    # build cart items for display
    @cart_items = @cart.map do |prod_id, qty|
      prod = @products.find { |p| p.id == prod_id.to_i }
      next unless prod
      { product: prod, quantity: qty.to_i, subtotal: prod.selling_price.to_i * qty.to_i }
    end.compact
    @total = @cart_items.sum { |i| i[:subtotal] }
  end

  def add
    prod_id = params[:product_id].to_s
    qty = params[:quantity].to_i.clamp(1, 99)
    session[:pesan_cart] ||= {}
    session[:pesan_cart][prod_id] = (session[:pesan_cart][prod_id].to_i + qty).clamp(1, 99)
    redirect_to pesan_path, notice: "Ditambahkan ke keranjang"
  end

  def update_qty
    prod_id = params[:product_id].to_s
    qty = params[:quantity].to_i
    session[:pesan_cart] ||= {}
    if qty <= 0
      session[:pesan_cart].delete(prod_id)
    else
      session[:pesan_cart][prod_id] = qty.clamp(1, 99)
    end
    redirect_to pesan_path
  end

  def remove
    session[:pesan_cart] ||= {}
    session[:pesan_cart].delete(params[:product_id].to_s)
    redirect_to pesan_path
  end

  def clear
    session[:pesan_cart] = {}
    redirect_to pesan_path
  end

  def checkout
    cart = session[:pesan_cart] || {}
    if cart.empty?
      redirect_to pesan_path, alert: "Keranjang kosong"
      return
    end
    name = params[:customer_name].to_s.strip
    klass = params[:customer_class].to_s.strip
    phone = params[:customer_phone].to_s.strip
    note = params[:note].to_s.strip

    if name.blank?
      redirect_to pesan_path, alert: "Nama wajib diisi"
      return
    end

    order = Order.create!(
      customer_name: name,
      customer_class: klass,
      customer_phone: phone,
      note: note,
      status: "Menunggu",
      total_amount: 0
    )

    total = 0
    cart.each do |prod_id, qty|
      prod = Product.find_by(id: prod_id)
      next unless prod
      price = prod.selling_price.to_i
      subtotal = price * qty.to_i
      order.order_items.create!(product: prod, quantity: qty.to_i, price: price, subtotal: subtotal)
      total += subtotal
    end

    if order.order_items.empty?
      order.destroy
      redirect_to pesan_path, alert: "Keranjang tidak valid"
      return
    end

    order.update!(total_amount: total)
    session[:pesan_cart] = {}
    session[:last_order_id] = order.id
    redirect_to pesan_sukses_path(order)
  end

  def sukses
    @order = Order.find(params[:id])
    # only allow owner via session
    unless session[:last_order_id].to_i == @order.id
      # still show but no restriction for demo
    end
  end

  private

  def load_products
    @products = Product.order(:name)
  end
end
