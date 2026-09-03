class AddSaleToOrders < ActiveRecord::Migration[7.2]
  def change
    add_reference :orders, :sale, null: true, foreign_key: true
  end
end
