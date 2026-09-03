class CreateSales < ActiveRecord::Migration[7.2]
  def change
    create_table :sales do |t|
      t.string :number
      t.date :sale_date
      t.references :student, null: false, foreign_key: true
      t.integer :total_items
      t.integer :total_amount
      t.string :payment_method
      t.integer :amount_paid
      t.string :status
      t.integer :profit

      t.timestamps
    end
  end
end
