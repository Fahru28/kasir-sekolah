require 'rails_helper'

RSpec.describe LlamaBotRails::ScaffoldColumns do
  FakeAttr = Struct.new(:name, :type)

  def attrs(*pairs)
    pairs.map { |name, type| FakeAttr.new(name.to_s, type) }
  end

  describe '.table_columns' do
    it 'caps selection at five columns in declaration order' do
      selected = described_class.table_columns(attrs(*%w[a b c d e f g].map { |n| [n, :string] }))
      expect(selected.map(&:name)).to eq(%w[a b c d e])
    end

    it 'puts priority names first, in priority order' do
      selected = described_class.table_columns(
        attrs(['zzz', :string], ['status', :string], ['email', :string], ['name', :string])
      )
      expect(selected.map(&:name)).to eq(%w[name email status zzz])
    end

    it 'excludes text, json, binary, rich_text, attachments and references' do
      selected = described_class.table_columns(
        attrs(['name', :string], ['notes', :text], ['payload', :jsonb], ['blob', :binary],
              ['body', :rich_text], ['avatar', :attachment], ['user', :references])
      )
      expect(selected.map(&:name)).to eq(%w[name])
    end

    it 'excludes sensitive and internal-id names' do
      selected = described_class.table_columns(
        attrs(['name', :string], ['password_digest', :string], ['api_token', :string],
              ['client_secret', :string], ['encrypted_ssn', :string], ['owner_id', :integer])
      )
      expect(selected.map(&:name)).to eq(%w[name])
    end

    it 'never selects timestamps as main columns' do
      selected = described_class.table_columns(
        attrs(['name', :string], ['created_at', :datetime], ['updated_at', :datetime])
      )
      expect(selected.map(&:name)).to eq(%w[name])
    end
  end

  describe '.created_at_column?' do
    it 'is true when a table slot is free' do
      expect(described_class.created_at_column?(attrs(['name', :string]))).to be(true)
    end

    it 'is false when five main columns are already selected' do
      full = attrs(*%w[a b c d e].map { |n| [n, :string] })
      expect(described_class.created_at_column?(full)).to be(false)
    end
  end

  describe '.searchable_columns' do
    it 'only includes string-typed table columns, capped at four' do
      selected = described_class.searchable_columns(
        attrs(['name', :string], ['age', :integer], ['email', :string],
              ['company', :string], ['status', :string], ['nickname', :string])
      )
      expect(selected.map(&:name).size).to eq(4)
      expect(selected.map(&:name)).to all(match(/name|email|company|status|nickname/))
    end

    it 'is empty for models with no short string fields' do
      expect(described_class.searchable_columns(attrs(['count', :integer]))).to be_empty
    end
  end

  describe '.boolean_columns' do
    it 'selects boolean attributes' do
      selected = described_class.boolean_columns(attrs(['name', :string], ['active', :boolean]))
      expect(selected.map(&:name)).to eq(%w[active])
    end
  end

  describe 'the Contact acceptance example' do
    it 'selects name, email, company, status (+ created_at) and excludes notes' do
      contact = attrs(['name', :string], ['email', :string], ['company', :string],
                      ['status', :string], ['notes', :text])
      expect(described_class.table_columns(contact).map(&:name)).to eq(%w[name email company status])
      expect(described_class.created_at_column?(contact)).to be(true)
      expect(described_class.searchable_columns(contact).map(&:name)).to eq(%w[name email company status])
    end
  end
end
