class CreateOrders < ActiveRecord::Migration[7.2]
  def change
    create_table :orders do |t|
      t.string :customer_name
      t.string :customer_class
      t.string :customer_phone
      t.text :note
      t.string :status
      t.integer :total_amount

      t.timestamps
    end
  end
end
