class CreateStockEntries < ActiveRecord::Migration[7.2]
  def change
    create_table :stock_entries do |t|
      t.string :number
      t.date :entry_date
      t.string :supplier
      t.references :product, null: false, foreign_key: true
      t.integer :quantity
      t.integer :cost_price
      t.string :note

      t.timestamps
    end
  end
end
