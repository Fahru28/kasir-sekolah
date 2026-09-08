class BackupsController < ApplicationController
  def index
    @students_count = Student.count
    @products_count = Product.count
    @sales_count = Sale.count
    @stock_entries_count = StockEntry.count
    @piutang_count = Sale.where(payment_method: "Piutang").where("status != ? OR status IS NULL", "Lunas").count
    @total_piutang = Sale.where(payment_method: "Piutang").sum { |s| s.outstanding rescue 0 }
  end

  def export
    require "caxlsx"
    p = Axlsx::Package.new
    wb = p.workbook

    # Styles
    header_style = wb.styles.add_style(bg_color: "4C3F6D", fg_color: "FFFFFF", b: true, alignment: { horizontal: :center, vertical: :center }, border: { style: :thin, color: "D9D9D9" })
    title_style = wb.styles.add_style(bg_color: "EDE9FE", fg_color: "4C3F6D", b: true, sz: 12, alignment: { horizontal: :center })
    sub_header_style = wb.styles.add_style(bg_color: "F3F4F6", b: true, alignment: { horizontal: :center })
    money_style = wb.styles.add_style(num_fmt: 3, alignment: { horizontal: :right })
    money_bold = wb.styles.add_style(num_fmt: 3, b: true, alignment: { horizontal: :right })
    center_style = wb.styles.add_style(alignment: { horizontal: :center })
    wrap_style = wb.styles.add_style(alignment: { wrap_text: true, vertical: :center })
    lunas_style = wb.styles.add_style(bg_color: "DCFCE7", fg_color: "166534", b: true, alignment: { horizontal: :center })
    belum_style = wb.styles.add_style(bg_color: "FEF3C7", fg_color: "92400E", b: true, alignment: { horizontal: :center })
    thin_border = { style: :thin, color: "D9D9D9" }

    # 1. Dashboard ringkasan
    wb.add_worksheet(name: "Dashboard") do |sheet|
      sheet.add_row ["BACKUP KASIR SEKOLAH - #{Date.current.strftime('%d %B %Y')}"], style: title_style, height: 24
      sheet.merge_cells("A1:D1")
      sheet.add_row ["Diekspor: #{Time.current.strftime('%d-%m-%Y %H:%M WIB')} | Total Penjualan: #{Sale.count} | Total Siswa: #{Student.count} | Total Barang: #{Product.count}"], style: wrap_style
      sheet.merge_cells("A2:D2")
      sheet.add_row []
      sheet.add_row ["Ringkasan", nil, nil, nil], style: header_style
      sheet.add_row ["Total Penjualan Hari Ini", Sale.where(sale_date: Date.current).sum(:total_amount).to_i], style: nil
      sheet.add_row ["Total Transaksi Hari Ini", Sale.where(sale_date: Date.current).count]
      sheet.add_row ["Total Keuntungan Hari Ini", Sale.where(sale_date: Date.current).sum(:profit).to_i]
      sheet.add_row ["Total Piutang Berjalan", Sale.where(payment_method: "Piutang").sum { |s| s.outstanding rescue 0 }], style: nil
      sheet.add_row ["Barang Stok Menipis", Product.all.count { |pp| pp.low_stock? rescue false }]
      sheet.column_widths 30, 20, 20, 20
    end

    # 2. Data_Anak
    wb.add_worksheet(name: "Data_Anak") do |sheet|
      sheet.add_row ["ID_Anak", "NIS", "Nama_Anak", "Kelas", "Nama_Wali", "WA", "Alamat", "Status_Aktif"], style: header_style
      Student.order(:code).each do |s|
        sheet.add_row [s.code, s.nis, s.name, s.class_name, s.guardian_name, s.phone, s.address, s.active? ? "Aktif" : "Nonaktif"]
      end
      sheet.column_widths 12, 12, 22, 8, 18, 16, 24, 12
      sheet.auto_filter = "A1:H1"
      sheet.sheet_view.pane do |pane|
        pane.state = :frozen
        pane.y_split = 1
        pane.x_split = 0
        pane.top_left_cell = "A2"
        pane.active_pane = :bottom_left
      end
    end

    # 3. Data_Barang
    wb.add_worksheet(name: "Data_Barang") do |sheet|
      sheet.add_row ["Kode_Barang", "Nama_Barang", "Kategori", "Satuan", "Harga_Modal", "Harga_Jual", "Stok_Awal", "Barang_Masuk", "Barang_Terjual", "Sisa_Stok", "Min_Stok", "Status"], style: header_style
      Product.order(:code).each do |pr|
        masuk = pr.stock_entries.sum(:quantity).to_i
        terjual = pr.sale_items.sum(:quantity).to_i
        sisa = pr.current_stock
        status = sisa <= pr.min_stock.to_i ? "STOK MENIPIS" : "Aman"
        row = sheet.add_row [pr.code, pr.name, pr.category, pr.unit, pr.cost_price.to_i, pr.selling_price.to_i, pr.initial_stock.to_i, masuk, terjual, sisa, pr.min_stock.to_i, status]
        # bold low stock
        if status == "STOK MENIPIS"
          row.cells[9].style = wb.styles.add_style(bg_color: "FECACA", fg_color: "991B1B", b: true, alignment: { horizontal: :center })
          row.cells[11].style = wb.styles.add_style(bg_color: "FECACA", fg_color: "991B1B", b: true, alignment: { horizontal: :center })
        end
      end
      sheet.column_widths 13, 22, 12, 10, 13, 13, 11, 13, 14, 11, 10, 14
      sheet.auto_filter = "A1:L1"
      sheet.sheet_view.pane do |pane|
        pane.state = :frozen
        pane.y_split = 1
        pane.x_split = 0
        pane.top_left_cell = "A2"
        pane.active_pane = :bottom_left
      end
    end

    # 4. Barang_Masuk
    wb.add_worksheet(name: "Barang_Masuk") do |sheet|
      sheet.add_row ["No_Pembelian", "Tanggal", "Supplier", "Kode_Barang", "Nama_Barang", "Jumlah", "Harga_Modal", "Total", "Keterangan"], style: header_style
      StockEntry.includes(:product).order(:entry_date).each do |e|
        total = e.quantity.to_i * e.cost_price.to_i
        sheet.add_row [e.number.presence || "IN-#{e.id.to_s.rjust(3,'0')}", e.entry_date, e.supplier, e.product&.code, e.product&.name, e.quantity.to_i, e.cost_price.to_i, total, e.note]
      end
      sheet.column_widths 15, 13, 18, 13, 22, 9, 13, 13, 20
      sheet.auto_filter = "A1:I1"
      sheet.sheet_view.pane do |pane|
        pane.state = :frozen
        pane.y_split = 1
        pane.x_split = 0
        pane.top_left_cell = "A2"
        pane.active_pane = :bottom_left
      end
    end

    # 5. Penjualan
    wb.add_worksheet(name: "Penjualan") do |sheet|
      sheet.add_row ["No_Transaksi", "Tanggal", "ID_Anak", "Nama_Anak", "Total_Item", "Total_Belanja", "Metode_Bayar", "Nominal_Bayar", "Kembalian_Piutang", "Status", "Keuntungan_Trx"], style: header_style
      Sale.includes(:student).order(:sale_date, :id).each do |s|
        kembalian = s.amount_paid.to_i - s.total_amount.to_i
        # For Piutang show negative outstanding
        kembalian_piutang = s.payment_method == "Piutang" ? -s.outstanding : kembalian
        status_style_needed = s.status == "Lunas" ? lunas_style : belum_style
        row = sheet.add_row [s.number, s.sale_date, s.student&.code, s.student&.name, s.total_items.to_i, s.total_amount.to_i, s.payment_method, s.amount_paid.to_i, kembalian_piutang, s.status, s.profit.to_i]
        row.cells[9].style = status_style_needed
      end
      sheet.column_widths 18, 13, 11, 18, 11, 14, 13, 14, 16, 13, 14
      sheet.auto_filter = "A1:K1"
      sheet.sheet_view.pane do |pane|
        pane.state = :frozen
        pane.y_split = 1
        pane.x_split = 0
        pane.top_left_cell = "A2"
        pane.active_pane = :bottom_left
      end
    end

    # 6. Detail_Penjualan
    wb.add_worksheet(name: "Detail_Penjualan") do |sheet|
      sheet.add_row ["No_Transaksi", "Kode_Barang", "Qty", "Harga_Jual", "Harga_Modal", "Subtotal", "Nama_Barang", "Keuntungan"], style: header_style
      SaleItem.includes(:sale, :product).joins(:sale).order("sales.sale_date", "sales.number").each do |d|
        sheet.add_row [d.sale.number, d.product&.code, d.quantity.to_i, d.selling_price.to_i, d.cost_price.to_i, d.subtotal.to_i, d.product&.name, d.profit.to_i]
      end
      sheet.column_widths 18, 13, 8, 13, 13, 13, 22, 13
      sheet.auto_filter = "A1:H1"
      sheet.sheet_view.pane do |pane|
        pane.state = :frozen
        pane.y_split = 1
        pane.x_split = 0
        pane.top_left_cell = "A2"
        pane.active_pane = :bottom_left
      end
    end

    # 7. Pembayaran_Piutang
    wb.add_worksheet(name: "Pembayaran_Piutang") do |sheet|
      sheet.add_row ["No_Transaksi", "Tanggal_Bayar", "Nominal_Bayar", "Sisa_Piutang_Setelah_Bayar", "Keterangan"], style: header_style
      DebtPayment.includes(sale: :student).order(:payment_date).each do |dp|
        # sisa after this payment: compute payments up to this date
        total_payments_up_to = dp.sale.debt_payments.where("payment_date <= ? OR payment_date IS NULL", dp.payment_date).sum(:amount).to_i
        sisa = dp.sale.total_amount.to_i - total_payments_up_to
        sheet.add_row [dp.sale.number, dp.payment_date, dp.amount.to_i, sisa, dp.note]
      end
      sheet.column_widths 18, 14, 14, 22, 24
      sheet.auto_filter = "A1:E1"
      sheet.sheet_view.pane do |pane|
        pane.state = :frozen
        pane.y_split = 1
        pane.x_split = 0
        pane.top_left_cell = "A2"
        pane.active_pane = :bottom_left
      end
    end

    # 8. Piutang (rekap yang belum lunas)
    wb.add_worksheet(name: "Piutang") do |sheet|
      sheet.add_row ["No_Transaksi", "Tanggal", "Siswa", "Kelas", "Total_Piutang", "Sudah_Dibayar", "Sisa_Piutang", "Status"], style: header_style
      Sale.includes(:student, :debt_payments).where(payment_method: "Piutang").order(:sale_date).each do |s|
        dibayar = s.debt_payments.sum(:amount).to_i
        sisa = s.outstanding
        next if sisa <= 0 && s.status == "Lunas" && false # keep all piutang history, even lunas
        row = sheet.add_row [s.number, s.sale_date, s.student&.name, s.student&.class_name, s.total_amount.to_i, dibayar, sisa, sisa <= 0 ? "Lunas" : "Belum Lunas"]
        row.cells[7].style = sisa <= 0 ? lunas_style : belum_style
      end
      sheet.column_widths 18, 13, 18, 9, 14, 14, 14, 13
      sheet.auto_filter = "A1:H1"
      sheet.sheet_view.pane do |pane|
        pane.state = :frozen
        pane.y_split = 1
        pane.x_split = 0
        pane.top_left_cell = "A2"
        pane.active_pane = :bottom_left
      end
    end

    filename = "Backup_Kasir_Sekolah_#{Date.current.strftime('%Y%m%d')}.xlsx"
    send_data p.to_stream.read, filename: filename, type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", disposition: "attachment"
  end
end
