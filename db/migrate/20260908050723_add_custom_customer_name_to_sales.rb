class AddCustomCustomerNameToSales < ActiveRecord::Migration[7.2]
  def change
    add_column :sales, :custom_customer_name, :string
  end
end
