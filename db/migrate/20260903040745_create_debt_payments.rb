class CreateDebtPayments < ActiveRecord::Migration[7.2]
  def change
    create_table :debt_payments do |t|
      t.references :sale, null: false, foreign_key: true
      t.date :payment_date
      t.integer :amount
      t.string :note

      t.timestamps
    end
  end
end
