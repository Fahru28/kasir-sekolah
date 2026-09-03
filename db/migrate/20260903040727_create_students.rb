class CreateStudents < ActiveRecord::Migration[7.2]
  def change
    create_table :students do |t|
      t.string :code
      t.string :nis
      t.string :name
      t.string :class_name
      t.string :guardian_name
      t.string :phone
      t.string :address
      t.boolean :active

      t.timestamps
    end
  end
end
