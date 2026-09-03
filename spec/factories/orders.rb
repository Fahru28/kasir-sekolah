FactoryBot.define do
  factory :order do
    customer_name { "MyString" }
    customer_class { "MyString" }
    customer_phone { "MyString" }
    note { "MyText" }
    status { "MyString" }
    total_amount { 1 }
  end
end
