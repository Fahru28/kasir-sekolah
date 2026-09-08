class MakeStudentOptionalOnSales < ActiveRecord::Migration[7.2]
  def change
    change_column_null :sales, :student_id, true
  end
end
