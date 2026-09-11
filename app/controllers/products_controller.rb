class ProductsController < ApplicationController
  def index
    @products = Product.with_stock_fast.order(:name)
    if params[:q].present?
      q = "%#{params[:q].strip}%"
      @products = @products.where("products.code ILIKE :q OR products.name ILIKE :q OR products.category ILIKE :q", q: q)
    end
    if params[:kategori].present? && params[:kategori] != "Semua"
      @products = @products.where(category: params[:kategori])
    end
  end

  def template
    package = Axlsx::Package.new
    wb = package.workbook
    wb.add_worksheet(name: "Data_Barang") do |sheet|
      sheet.add_row %w[Kode_Barang Nama_Barang Kategori Satuan Harga_Modal Harga_Jual Stok Min_Stok]
      sheet.add_row ["B-016", "Contoh Barang", "Alat Tulis", "Pcs", 5000, 7000, 20, 5]
      sheet.add_row ["B-017", "Contoh Minuman", "Minuman", "Botol", 3000, 5000, 30, 10]
    end
    send_data package.to_stream.read, filename: "Template_Data_Barang.xlsx", type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  end

  def import_form
  end

  def import
    file = params[:file]
    return redirect_to import_form_products_path, alert: "Pilih file Excel dulu." if file.blank?
    ext = File.extname(file.original_filename).downcase
    begin
      rows = if ext == ".csv"
        require "csv"
        CSV.read(file.path, headers: true).map { |r| r.to_h }
      else
        xlsx = Roo::Spreadsheet.open(file.path, extension: ext.delete("."))
        xlsx.default_sheet = xlsx.sheets.first
        header = xlsx.row(1).map { |h| h.to_s.strip }
        (2..xlsx.last_row).map do |i|
          row = xlsx.row(i)
          header.each_with_index.to_h { |h, idx| [h, row[idx]] }
        end
      end
    rescue => e
      return redirect_to import_form_products_path, alert: "Gagal membaca file: #{e.message}"
    end

    created = 0; updated = 0; errors = []
    rows.each_with_index do |r, idx|
      norm = {}; r.each { |k,v| norm[k.to_s.strip.downcase] = v.to_s.strip }
      code = norm["kode_barang"] || norm["kode"] || norm["code"]
      name = norm["nama_barang"] || norm["nama"] || norm["name"]
      next if code.blank? && name.blank?
      if code.blank?
        errors << "Baris #{idx+2}: Kode_Barang kosong"; next
      end
      if name.blank?
        errors << "Baris #{idx+2}: Nama_Barang kosong (#{code})"; next
      end
      p = Product.find_or_initialize_by(code: code)
      is_new = p.new_record?
      stok_val = (norm["stok"] || norm["stok_awal"] || norm["initial_stock"] || "0").to_i
      is_new_for_stok = p.new_record?
      p.assign_attributes(
        name: name,
        category: (norm["kategori"] || norm["category"] || p.category || "Lain-lain").presence,
        unit: (norm["satuan"] || norm["unit"] || p.unit || "Pcs").presence,
        cost_price: (norm["harga_modal"] || norm["modal"] || p.cost_price || 0).to_s.delete(",.").to_i,
        selling_price: (norm["harga_jual"] || norm["jual"] || p.selling_price || 0).to_s.delete(",.").to_i,
        min_stock: (norm["min_stok"] || norm["min"] || p.min_stock || 5).to_i
      )
      # Stok diisi via initial_stock hanya untuk barang baru (barang lama atur via Tambah Stok)
      p.initial_stock = stok_val if is_new_for_stok
      # handle numbers with commas: "3,000" -> 3000; to_i already handles stripped
      # Fix cost/selling if original had dots
      if p.save
        is_new ? created += 1 : updated += 1
      else
        errors << "Baris #{idx+2} (#{code}): #{p.errors.full_messages.join(', ')}"
      end
    end
    msg = "Import selesai: #{created} baru, #{updated} diperbarui."
    msg += " Ada #{errors.size} error." if errors.any?
    flash[:import_errors] = errors.first(10) if errors.any?
    redirect_to products_path, notice: msg
  end

  def show
    @product = Product.find(params[:id])
  end

  def new
    @product = Product.new
  end

  def create
    stok = params[:product].delete(:current_stock).to_i
    @product = Product.new(product_params)
    @product.initial_stock = stok
    if @product.save
      redirect_to products_path, notice: "Barang ditambahkan (stok #{stok})"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @product = Product.find(params[:id])
  end

  def update
    @product = Product.find(params[:id])
    if @product.update(product_params)
      redirect_to products_path, notice: "Barang diperbarui"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @product = Product.find(params[:id])
    if @product.sale_items.exists?
      redirect_to products_path, alert: "Tidak bisa hapus #{@product.name}: masih ada transaksi penjualan yang pakai barang ini (#{@product.sale_items.count} transaksi). Hapus transaksi dulu atau nonaktifkan stok jadi 0." and return
    end
    if @product.order_items.exists?
      redirect_to products_path, alert: "Tidak bisa hapus #{@product.name}: masih ada pesanan online yang pakai barang ini (#{@product.order_items.count} pesanan)." and return
    end
    @product.destroy
    if @product.destroyed?
      redirect_to products_path, notice: "Barang #{@product.name} dihapus"
    else
      redirect_to products_path, alert: "Gagal hapus: #{@product.errors.full_messages.join(', ')}"
    end
  end

  def add_stock
    @product = Product.find(params[:id])
    qty = params[:quantity].to_i
    if qty <= 0
      redirect_to products_path, alert: "Jumlah stok harus > 0" and return
    end
    StockEntry.create!(
      number: "STK-#{Time.current.strftime('%Y%m%d%H%M%S')}-#{@product.id}",
      entry_date: Date.current,
      supplier: params[:supplier].presence || "Tambah stok manual",
      product: @product,
      quantity: qty,
      cost_price: @product.cost_price,
      note: params[:note].presence || "Tambah stok dari Data Barang"
    )
    redirect_to products_path, notice: "Stok #{@product.name} +#{qty} berhasil"
  end

  def adjust_stock
    @product = Product.find(params[:id])
    target = params[:target_stock].to_i
    if target < 0
      redirect_to products_path, alert: "Stok tidak boleh negatif" and return
    end
    current = @product.current_stock
    diff = target - current
    if diff == 0
      redirect_to products_path, notice: "Stok #{@product.name} tetap #{current}" and return
    end
    if diff > 0
      StockEntry.create!(
        number: "ADJ-#{Time.current.strftime('%Y%m%d%H%M%S')}-#{@product.id}",
        entry_date: Date.current,
        supplier: "Penyesuaian stok",
        product: @product,
        quantity: diff,
        cost_price: @product.cost_price,
        note: params[:note].presence || "Penyesuaian: #{current} → #{target} (+#{diff})"
      )
    else
      # Kurangi stok: simpan sebagai StockEntry negatif via catatan + kurangi initial_stock jika perlu
      # Paling simpel: catat penyesuaian negatif sebagai StockEntry dengan quantity negatif (izinkan khusus adjust)
      StockEntry.create!(
        number: "ADJ-#{Time.current.strftime('%Y%m%d%H%M%S')}-#{@product.id}",
        entry_date: Date.current,
        supplier: "Penyesuaian stok",
        product: @product,
        quantity: diff,
        cost_price: @product.cost_price,
        note: params[:note].presence || "Penyesuaian: #{current} → #{target} (#{diff})"
      )
    end
    redirect_to products_path, notice: "Stok #{@product.name}: #{current} → #{target} berhasil"
  end

  private

  def product_params
    params.require(:product).permit(:code, :name, :category, :unit, :cost_price, :selling_price, :min_stock)
  end
end
