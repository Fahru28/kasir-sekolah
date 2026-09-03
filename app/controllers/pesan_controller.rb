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
  end

  def download
    order = Order.find(params[:id])
    # Render struk sebagai PNG via HTML canvas — tapi untuk server-side kita bikin PNG sederhana
    # Pakai Ruby: generate PNG struk pesanan
    require "chunky_png" rescue nil
    # Fallback: kalau ChunkyPNG tidak ada, tetap kirim Excel biar tidak error
    unless defined?(ChunkyPNG)
      # coba kirim PDF-simple / tetap Excel kalau gem belum ada
      package = Axlsx::Package.new
      wb = package.workbook
      wb.add_worksheet(name: "Pesanan") do |sheet|
        sheet.add_row ["Unit Layanan Pendidikan — SIT Insantama"]
        sheet.add_row ["No. Pesanan", "##{order.id}"]
        sheet.add_row ["Tanggal", order.created_at.strftime("%d %b %Y %H:%M")]
        sheet.add_row ["Nama", order.customer_name]
        sheet.add_row ["Kelas", order.customer_class]
        sheet.add_row ["WA", order.customer_phone]
        sheet.add_row ["Catatan", order.note]
        sheet.add_row ["Status", order.status_label]
        sheet.add_row []
        sheet.add_row ["Barang", "Qty", "Harga", "Subtotal"]
        order.order_items.includes(:product).each do |oi|
          sheet.add_row [oi.product.name, oi.quantity, oi.price, oi.subtotal]
        end
        sheet.add_row []
        sheet.add_row ["TOTAL", "", "", order.total_amount]
      end
      send_data package.to_stream.read, filename: "pesanan-#{order.id}.xlsx", type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      return
    end

    # --- PNG struk dengan ChunkyPNG ---
    width = 600
    header_h = 90
    row_h = 28
    footer_h = 90
    n = order.order_items.size
    height = header_h + 30 + (n + 1) * row_h + footer_h

    png = ChunkyPNG::Image.new(width, height, ChunkyPNG::Color::WHITE)
    # header hijau
    header_color = ChunkyPNG::Color.from_hex("#059669")
    (0...header_h).each do |y|
      (0...width).each { |x| png[x, y] = header_color }
    end
    # helpers
    def draw_text_png(png, x, y, text, size: 14, color: ChunkyPNG::Color::BLACK)
      # ChunkyPNG tidak punya text renderer bagus — kita pakai fallback: gambar sudah ada
      # Untuk sekarang, PNG kosong dengan garis; text akan di-render via HTML2Canvas di browser
      # Jadi download tetap route ke HTML image
    end

    # Sederhana: PNG putih dengan border — text akan diganti client-side download
    # Kirim Excel saja kalau di server belum bisa render text ke PNG secara bagus
    package = Axlsx::Package.new
    wb = package.workbook
    wb.add_worksheet(name: "Pesanan") do |sheet|
      sheet.add_row ["Unit Layanan Pendidikan — SIT Insantama"]
      sheet.add_row ["No. Pesanan", "##{order.id}"]
      sheet.add_row ["Tanggal", order.created_at.strftime("%d %b %Y %H:%M")]
      sheet.add_row ["Nama", order.customer_name]
      sheet.add_row ["Kelas", order.customer_class]
      sheet.add_row ["WA", order.customer_phone]
      sheet.add_row ["Catatan", order.note]
      sheet.add_row ["Status", order.status_label]
      sheet.add_row []
      sheet.add_row ["Barang", "Qty", "Harga", "Subtotal"]
      order.order_items.includes(:product).each do |oi|
        sheet.add_row [oi.product.name, oi.quantity, oi.price, oi.subtotal]
      end
      sheet.add_row []
      sheet.add_row ["TOTAL", "", "", order.total_amount]
    end
    send_data package.to_stream.read, filename: "pesanan-#{order.id}.xlsx", type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  end

  private

  def load_products
    @products = Product.order(:name)
  end
end
