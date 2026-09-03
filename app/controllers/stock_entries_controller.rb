class StockEntriesController < ApplicationController
  def index
    @entries = StockEntry.includes(:product).order(entry_date: :desc)
    @products = Product.order(:name)
  end

  def template
    package = Axlsx::Package.new
    wb = package.workbook
    wb.add_worksheet(name: "Barang_Masuk") do |sheet|
      sheet.add_row %w[No_Pembelian Tanggal Supplier Kode_Barang Jumlah Keterangan]
      sheet.add_row ["IN-003", Date.current.to_s, "Toko Contoh", "B-001", 20, "Stok tambahan"]
    end
    send_data package.to_stream.read, filename: "Template_Barang_Masuk.xlsx", type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  end

  def import_form
  end

  def import
    file = params[:file]
    return redirect_to import_form_stock_entries_path, alert: "Pilih file Excel dulu." if file.blank?
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
      return redirect_to import_form_stock_entries_path, alert: "Gagal membaca file: #{e.message}"
    end

    created = 0; skipped = 0; errors = []
    rows.each_with_index do |r, idx|
      norm = {}; r.each { |k,v| norm[k.to_s.strip.downcase] = v.to_s.strip }
      num = norm["no_pembelian"] || norm["no"] || norm["number"]
      code = norm["kode_barang"] || norm["kode"] || norm["code"]
      qty = (norm["jumlah"] || norm["qty"] || norm["quantity"] || "0").to_i
      next if num.blank? && code.blank? && qty == 0
      if num.blank?
        errors << "Baris #{idx+2}: No_Pembelian kosong"; next
      end
      if StockEntry.exists?(number: num)
        skipped += 1; next
      end
      product = Product.find_by(code: code)
      if product.nil?
        errors << "Baris #{idx+2} (#{num}): Kode_Barang #{code} tidak ditemukan di Data Barang"; next
      end
      if qty <= 0
        errors << "Baris #{idx+2} (#{num}): Jumlah harus > 0"; next
      end
      date_str = norm["tanggal"] || norm["date"] || Date.current.to_s
      begin
        d = Date.parse(date_str)
      rescue
        d = Date.current
      end
      supplier = norm["supplier"] || norm["pemasok"] || ""
      note = norm["keterangan"] || norm["note"] || ""
      cost = product.cost_price
      e = StockEntry.new(number: num, entry_date: d, supplier: supplier, product: product, quantity: qty, cost_price: cost, note: note)
      if e.save
        created += 1
      else
        errors << "Baris #{idx+2} (#{num}): #{e.errors.full_messages.join(', ')}"
      end
    end
    msg = "Import selesai: #{created} ditambahkan, #{skipped} di-skip (sudah ada)."
    msg += " Ada #{errors.size} error." if errors.any?
    flash[:import_errors] = errors.first(10) if errors.any?
    redirect_to stock_entries_path, notice: msg
  end

  def create
    @entry = StockEntry.new(entry_params)
    if @entry.save
      redirect_to stock_entries_path, notice: "Stok masuk dicatat"
    else
      @entries = StockEntry.includes(:product).order(entry_date: :desc)
      @products = Product.order(:name)
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    @entry = StockEntry.find(params[:id])
    @entry.destroy
    redirect_to stock_entries_path, notice: "Entri dihapus"
  end

  private

  def entry_params
    params.require(:stock_entry).permit(:number, :entry_date, :supplier, :product_id, :quantity, :cost_price, :note)
  end
end
