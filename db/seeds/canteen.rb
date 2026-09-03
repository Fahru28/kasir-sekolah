puts "Seeding canteen data from spreadsheet..."

students = [
  ["A-001","1001","Budi Santoso","1A","Agus Santoso","08123456701","Jl. Merdeka 1",true],
  ["A-002","1002","Siti Aminah","1B","Ahmad","08123456702","Jl. Sudirman 2",true],
  ["A-003","1003","Andi Wijaya","2A","Budi W","08123456703","Jl. Mawar 3",true],
  ["A-004","1004","Rina Melati","2B","Hasan","08123456704","Jl. Melati 4",true],
  ["A-005","1005","Dika Pratama","3A","Joko","08123456705","Jl. Anggrek 5",true],
  ["A-006","1006","Nisa Kamil","3B","Kamil","08123456706","Jl. Kenanga 6",true],
  ["A-007","1007","Fajar Siddiq","1A","Siddiq","08123456707","Jl. Kamboja 7",true],
  ["A-008","1008","Lestari","1B","Parno","08123456708","Jl. Dahlia 8",true],
  ["A-009","1009","Reza Rahadian","2A","Rahman","08123456709","Jl. Flamboyan 9",true],
  ["A-010","1010","Ayu Ting","2B","Ting","08123456710","Jl. Teratai 10",true],
]
students.each do |code, nis, name, klass, guardian, phone, addr, active|
  Student.find_or_create_by!(code: code) do |s|
    s.nis = nis; s.name = name; s.class_name = klass; s.guardian_name = guardian
    s.phone = phone; s.address = addr; s.active = active
  end
end

products = [
  ["B-001","Buku Tulis Sinar","Alat Tulis","Pcs",3000,4000,50,10],
  ["B-002","Pensil 2B","Alat Tulis","Pcs",1000,2000,100,20],
  ["B-003","Penghapus","Alat Tulis","Pcs",500,1000,50,10],
  ["B-004","Penggaris 30cm","Alat Tulis","Pcs",1500,2500,30,5],
  ["B-005","Air Mineral 600ml","Minuman","Botol",2500,3500,100,20],
  ["B-006","Susu Coklat","Minuman","Kotak",3500,5000,50,10],
  ["B-007","Roti Coklat","Makanan","Bungkus",2000,3000,40,10],
  ["B-008","Biskuit","Makanan","Bungkus",1500,2500,60,15],
  ["B-009","Nasi Kuning","Makanan","Bungkus",5000,7000,20,5],
  ["B-010","Seragam SD Putih","Seragam","Pcs",45000,60000,20,5],
  ["B-011","Seragam SD Merah","Seragam","Pcs",45000,60000,20,5],
  ["B-012","Dasi SD","Seragam","Pcs",5000,10000,30,10],
  ["B-013","Topi SD","Seragam","Pcs",10000,15000,30,10],
  ["B-014","Buku Gambar A4","Alat Tulis","Pcs",4000,6000,40,10],
  ["B-015","Spidol Hitam","Alat Tulis","Pcs",6000,8500,25,5],
]
products.each do |code, name, cat, unit, cost, sell, init, min|
  Product.find_or_create_by!(code: code) do |p|
    p.name = name; p.category = cat; p.unit = unit; p.cost_price = cost
    p.selling_price = sell; p.initial_stock = init; p.min_stock = min
  end
end

# Stock entries (Barang_Masuk)
[
  ["IN-001", Date.parse("2026-09-01"), "Toko ATK", "B-001", 50, 3000, "Stok Bulanan"],
  ["IN-002", Date.parse("2026-09-01"), "Toko ATK", "B-002", 100, 1000, "Stok Bulanan"],
].each do |num, date, supplier, code, qty, cost, note|
  prod = Product.find_by!(code: code)
  StockEntry.find_or_create_by!(number: num) do |e|
    e.entry_date = date; e.supplier = supplier; e.product = prod
    e.quantity = qty; e.cost_price = cost; e.note = note
  end
end

# Sales + items
budi = Student.find_by!(code: "A-001")
siti = Student.find_by!(code: "A-002")

sale1 = Sale.find_or_create_by!(number: "TRX-20260901-001") do |s|
  s.sale_date = Date.parse("2026-09-01")
  s.student = budi
  s.total_items = 3
  s.total_amount = 11500
  s.payment_method = "Tunai"
  s.amount_paid = 15000
  s.status = "Lunas"
  s.profit = 3000
end

sale2 = Sale.find_or_create_by!(number: "TRX-20260902-002") do |s|
  s.sale_date = Date.parse("2026-09-02")
  s.student = siti
  s.total_items = 1
  s.total_amount = 60000
  s.payment_method = "Piutang"
  s.amount_paid = 0
  s.status = "Belum Lunas"
  s.profit = 15000
end

[
  [sale1, "B-001", 2, 4000, 3000],
  [sale1, "B-005", 1, 3500, 2500],
  [sale2, "B-010", 1, 60000, 45000],
].each do |sale, code, qty, sell, cost|
  prod = Product.find_by!(code: code)
  SaleItem.find_or_create_by!(sale: sale, product: prod) do |si|
    si.quantity = qty; si.selling_price = sell; si.cost_price = cost
    si.subtotal = qty * sell; si.profit = qty * (sell - cost)
  end
end

puts "Done: #{Student.count} students, #{Product.count} products, #{StockEntry.count} stock entries, #{Sale.count} sales, #{SaleItem.count} items"
