# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#

User.find_or_create_by!(email: 'kody@llamapress.ai') do |user|
  user.password = '123456'
  user.password_confirmation = '123456'
end

User.find_or_create_by!(email: 'admin@sitin.s.sch.id') do |user|
  user.password = 'insantama123'
  user.password_confirmation = 'insantama123'
end

load Rails.root.join('db/seeds/canteen.rb')

# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end
