FactoryBot.define do
  factory :order_item do
    order { nil }
    product { nil }
    quantity { 1 }
    price { 1 }
    subtotal { 1 }
  end
end
