require 'rails_helper'

RSpec.describe LlamaBotRails::ScaffoldFiltering do
  # Minimal harness standing in for a generated controller.
  let(:harness_class) do
    Class.new do
      include LlamaBotRails::ScaffoldFiltering
      attr_accessor :params

      public :llama_filtered_scope, :llama_parse_date, :llama_paginate
    end
  end

  let(:harness) { harness_class.new }

  def with_params(hash)
    harness.params = ActionController::Parameters.new(hash)
    harness
  end

  let!(:alpha) do
    LlamaBotRails::Release.create!(title: 'Alpha launch', version: '1.0.0', published: true)
  end
  let!(:percent) do
    LlamaBotRails::Release.create!(title: '100% coverage', version: '1.1.0', published: false)
  end
  let!(:underscore) do
    LlamaBotRails::Release.create!(title: 'snake_case title', version: '1.2.0', published: false)
  end

  describe '#llama_filtered_scope' do
    def filtered(params)
      with_params(params).llama_filtered_scope(
        LlamaBotRails::Release.all,
        search_columns: %i[title version],
        boolean_columns: %i[published],
        date_column: :created_at
      )
    end

    it 'matches a plain search term across the allowlisted columns' do
      expect(filtered(q: 'Alpha')).to contain_exactly(alpha)
      expect(filtered(q: '1.2.0')).to contain_exactly(underscore)
    end

    it 'treats % and _ as literal characters, not wildcards' do
      expect(filtered(q: '100%')).to contain_exactly(percent)
      expect(filtered(q: '%')).to contain_exactly(percent)
      expect(filtered(q: 'snake_case')).to contain_exactly(underscore)
      # A bare underscore must not act as a single-character wildcard.
      expect(filtered(q: '_')).to contain_exactly(underscore)
    end

    it 'applies boolean filters only for explicit true/false values' do
      expect(filtered(published: 'true')).to contain_exactly(alpha)
      expect(filtered(published: 'false')).to contain_exactly(percent, underscore)
      expect(filtered(published: 'bogus')).to contain_exactly(alpha, percent, underscore)
    end

    it 'silently ignores malformed dates instead of raising' do
      expect(filtered(from: 'not-a-date').count).to eq(3)
      expect(filtered(to: '2026-99-99').count).to eq(3)
      expect(filtered(from: { evil: 'hash' }).count).to eq(3)
    end

    it 'applies a valid created-at range' do
      expect(filtered(from: Date.yesterday.iso8601).count).to eq(3)
      expect(filtered(to: Date.yesterday.iso8601).count).to eq(0)
    end
  end

  describe '#llama_parse_date' do
    it 'parses ISO dates and rejects everything else' do
      expect(harness.llama_parse_date('2026-07-22')).to eq(Date.new(2026, 7, 22))
      expect(harness.llama_parse_date('07/22/2026')).to be_nil
      expect(harness.llama_parse_date(nil)).to be_nil
      expect(harness.llama_parse_date(['2026-07-22'])).to be_nil
    end
  end

  describe '#llama_paginate' do
    it 'clamps per_page to the maximum' do
      pagination, _records = with_params(per_page: '999999').llama_paginate(LlamaBotRails::Release.all)
      expect(pagination.limit).to eq(described_class::MAX_PER_PAGE)
    end

    it 'defaults nonsense per_page and page values' do
      pagination, records = with_params(per_page: '-5', page: '0').llama_paginate(LlamaBotRails::Release.all)
      expect(pagination.limit).to eq(described_class::DEFAULT_PER_PAGE)
      expect(pagination.page).to eq(1)
      expect(records.count).to eq(3)
    end

    it 'never 500s on an out-of-range page' do
      pagination, records = with_params(page: '9999').llama_paginate(LlamaBotRails::Release.all)
      expect(records.count).to be > 0
      expect(pagination.page).to be <= pagination.pages
    end

    it 'paginates' do
      pagination, records = with_params(per_page: '2', page: '2').llama_paginate(
        LlamaBotRails::Release.order(:id)
      )
      expect(records.count).to eq(1)
      expect(pagination.pages).to eq(2)
      expect(pagination.prev).to eq(1)
      expect(pagination.next).to be_nil
    end
  end
end
