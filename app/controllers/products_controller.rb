class ProductsController < ApplicationController
  def index
    @products = Product.order(:name)
  end

  def template
    package = Axlsx::Package.new
    wb = package.workbook
    wb.add_worksheet(name: "Data_Barang") do |sheet|
      sheet.add_row %w[Kode_Barang Nama_Barang Kategori Satuan Harga_Modal Harga_Jual Stok_Awal Min_Stok]
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
      p.assign_attributes(
        name: name,
        category: (norm["kategori"] || norm["category"] || p.category || "Lain-lain").presence,
        unit: (norm["satuan"] || norm["unit"] || p.unit || "Pcs").presence,
        cost_price: (norm["harga_modal"] || norm["modal"] || p.cost_price || 0).to_s.delete(",.").to_i,
        selling_price: (norm["harga_jual"] || norm["jual"] || p.selling_price || 0).to_s.delete(",.").to_i,
        initial_stock: (norm["stok_awal"] || norm["stok"] || norm["initial_stock"] || p.initial_stock || 0).to_i,
        min_stock: (norm["min_stok"] || norm["min"] || p.min_stock || 5).to_i
      )
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
    @product = Product.new(product_params)
    if @product.save
      redirect_to products_path, notice: "Barang ditambahkan"
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
    @product.destroy
    redirect_to products_path, notice: "Barang dihapus"
  end

  private

  def product_params
    params.require(:product).permit(:code, :name, :category, :unit, :cost_price, :selling_price, :initial_stock, :min_stock)
  end
end
