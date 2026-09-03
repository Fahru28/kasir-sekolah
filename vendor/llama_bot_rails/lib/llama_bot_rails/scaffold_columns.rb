module LlamaBotRails
  # Deterministic column selection for the LlamaPress scaffold templates.
  #
  # Operates at GENERATE time on Rails::Generators::GeneratedAttribute-like
  # objects (anything responding to #name and #type). Pure functions: the same
  # attribute list always yields the same selection, so generated output is
  # reproducible and testable without a database.
  #
  # Rules (see docs/scaffold_templates.md):
  # - At most MAX_TABLE_COLUMNS columns in the index table; `created_at` is
  #   appended as a final informational column only when there is room.
  # - PRIORITY_NAMES win the first slots, in the order listed here; remaining
  #   slots fill from short scalar fields in declaration order.
  # - Long/opaque/sensitive fields (text, JSON, binary, attachments, password/
  #   token/secret-ish names, foreign keys) never auto-select for the table or
  #   search; they still appear in the generated drawer show/form views.
  module ScaffoldColumns
    MAX_TABLE_COLUMNS = 5
    MAX_SEARCH_COLUMNS = 4
    PRIORITY_NAMES = %w[name title subject full_name username email company status].freeze
    EXCLUDED_TYPES = %i[
      text json jsonb binary rich_text attachment attachments
      references belongs_to
    ].freeze
    EXCLUDED_NAME_PATTERN = /password|digest|token|secret|encrypted|\Aid\z|_id\z/
    TIMESTAMP_NAMES = %w[created_at updated_at].freeze

    module_function

    # Attributes that may appear as a main table column.
    def eligible?(attribute)
      name = attribute.name.to_s
      !EXCLUDED_TYPES.include?(attribute.type&.to_sym) &&
        name !~ EXCLUDED_NAME_PATTERN &&
        !TIMESTAMP_NAMES.include?(name)
    end

    # Up to MAX_TABLE_COLUMNS attributes, priority names first, then
    # declaration order. Does NOT include created_at — see created_at_column?.
    def table_columns(attributes)
      eligible = attributes.select { |a| eligible?(a) }
      eligible
        .sort_by.with_index { |a, i| [priority_index(a), i] }
        .take(MAX_TABLE_COLUMNS)
    end

    # created_at joins the table as a final informational column when a slot
    # is free (timestamps are on by default for scaffolds).
    def created_at_column?(attributes)
      table_columns(attributes).size < MAX_TABLE_COLUMNS
    end

    # The linked, always-visible first column. Nil when no attribute is
    # eligible (templates then link the record id).
    def primary_column(attributes)
      table_columns(attributes).first
    end

    def secondary_columns(attributes)
      table_columns(attributes).drop(1)
    end

    # Short string fields the generated text search may cover.
    def searchable_columns(attributes)
      table_columns(attributes)
        .select { |a| a.type&.to_sym == :string }
        .take(MAX_SEARCH_COLUMNS)
    end

    # Boolean attributes get a simple Any/Yes/No filter.
    def boolean_columns(attributes)
      attributes.select { |a| a.type&.to_sym == :boolean }
    end

    def priority_index(attribute)
      PRIORITY_NAMES.index(attribute.name.to_s) || PRIORITY_NAMES.size
    end
  end
end
