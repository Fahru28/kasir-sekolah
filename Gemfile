source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 7.2.2", ">= 7.2.2.1"
# Rails' own strings — dates, number formats, validation messages — in ~80
# languages. Rails itself ships English only, so without this any app that
# adds a second language renders "Translation missing" for all of them.
gem "rails-i18n", "~> 7.0"
# The original asset pipeline for Rails [https://github.com/rails/sprockets-rails]
gem "sprockets-rails"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Use Tailwind CSS [https://github.com/rails/tailwindcss-rails]
gem "tailwindcss-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"
# Use Redis adapter to run Action Cable in production
# gem "redis", ">= 4.0.1"

# Use Kredis to get higher-level data types in Redis [https://github.com/rails/kredis]
# gem "kredis"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  gem "rubocop", require: false
  gem "rubocop-rspec", require: false
  gem "rspec-rails", "~> 7.0"
  gem "factory_bot_rails", "~> 6.4"
  gem "faker", "~> 3.5"
  gem "simplecov", require: false
  gem "byebug", "~> 12.0"

  # HTML validity linting - prevents missing closing tags that break JS-driven UIs
  gem "erb_lint", require: false

  # Reports missing/unused translation keys and normalises locale YAML:
  # `bundle exec i18n-tasks health`
  gem "i18n-tasks", "~> 1.0", require: false
  gem "better_html", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "cuprite"
  gem "database_cleaner-active_record", "~> 2.2"
  gem "mutant-rspec"
  gem "prop_check"
  gem "pact"
  gem "rspec-snapshot", require: false
  gem "shoulda-matchers", "~> 6.0"
end

# llama_bot_rails: pakai local path kalau submodule ada, fallback ke github kalau build di Railway/host tanpa submodule
if File.exist?("vendor/llama_bot_rails/llama_bot_rails.gemspec")
  gem "llama_bot_rails", path: "vendor/llama_bot_rails"
else
  gem "llama_bot_rails", github: "KodyKendall/llama_bot_rails"
end

gem "devise", "~> 4.9"

# Optional two-factor authentication (opt-in per project/user).
# See config/initializers/leonardo_two_factor.rb and
# app/models/concerns/two_factor_authenticatable_user.rb
gem "devise-two-factor", "~> 6.4"
gem "rotp"
gem "rqrcode", "~> 3.0"

# Optional passkey (WebAuthn) authentication (opt-in per project/user).
# See config/initializers/leonardo_passkeys.rb and
# app/models/concerns/passkey_authenticatable_user.rb
#
# PINNED EXACT ON PURPOSE. devise-webauthn is pre-1.0 and shipped breaking
# changes in both 0.4.0 and 0.5.0. Generated passkey code lives in each
# customer's overlay repo while this gem lives in the image, so a range
# constraint would break sign-in fleet-wide on the next image push.
# Bumping this is a fleet migration with its own QA pass.
gem "devise-webauthn", "0.5.0"

gem "pretender"

gem "pundit", "~> 2.4"

gem "dotenv-rails", "~> 3.1"

gem "twilio-ruby", "~> 7.6"
gem "plaid-ruby", "~> 0.1.2"
gem "stripe", "~> 15.5"

gem "image_processing", "~> 1.14"

gem "aws-sdk-s3"

gem "grover"

gem "roo", "~> 2.10"
gem "roo-xls", "~> 1.2"

gem "caxlsx"
gem "caxlsx_rails"

# Word document (.docx) generation from .docx templates with merge fields.
# (caracal was rejected: it pins rubyzip ~> 1.1, which force-downgrades caxlsx.)
gem "sablon", "~> 0.4"

gem "pagy", "~> 9.0"

gem "rack-attack", "~> 6.7"
gem "paper_trail", "~> 15.2"

gem "googleauth"
gem "google-apis-gmail_v1"

gem "web-push", "~> 3.1"
