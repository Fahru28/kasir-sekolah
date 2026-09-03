class CreateProducts < ActiveRecord::Migration[7.2]
  def change
    create_table :products do |t|
      t.string :code
      t.string :name
      t.string :category
      t.string :unit
      t.integer :cost_price
      t.integer :selling_price
      t.integer :initial_stock
      t.integer :min_stock

      t.timestamps
    end
  end
end
