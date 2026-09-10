class AddPerformanceIndexes < ActiveRecord::Migration[7.2]
  def change
    add_index :sales, :sale_date unless index_exists?(:sales, :sale_date)
    add_index :sales, :payment_method unless index_exists?(:sales, :payment_method)
    add_index :sales, :status unless index_exists?(:sales, :status)
    add_index :sales, :number, unique: true unless index_exists?(:sales, :number)
    add_index :products, :code, unique: true unless index_exists?(:products, :code)
    add_index :students, :code, unique: true unless index_exists?(:students, :code)
    add_index :orders, :status unless index_exists?(:orders, :status)
    add_index :stock_entries, :entry_date unless index_exists?(:stock_entries, :entry_date)
    add_index :debt_payments, :payment_date unless index_exists?(:debt_payments, :payment_date)
  end
end
