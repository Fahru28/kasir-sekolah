class CreateSaleItems < ActiveRecord::Migration[7.2]
  def change
    create_table :sale_items do |t|
      t.references :sale, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.integer :quantity
      t.integer :selling_price
      t.integer :cost_price
      t.integer :subtotal
      t.integer :profit

      t.timestamps
    end
  end
end
