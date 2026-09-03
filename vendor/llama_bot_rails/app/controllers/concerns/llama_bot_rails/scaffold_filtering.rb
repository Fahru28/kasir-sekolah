module LlamaBotRails
  # Runtime behavior shared by controllers generated from the LlamaPress
  # scaffold templates. Lives in the gem so escaping/pagination fixes reach
  # every app via a gem update, without regenerating controllers.
  #
  # Works with or without Pagy, and with or without an authenticated user.
  module ScaffoldFiltering
    extend ActiveSupport::Concern

    DEFAULT_PER_PAGE = 25
    MAX_PER_PAGE = 100

    # Pagy-compatible subset used when Pagy is not available in the host.
    Page = Struct.new(:page, :pages, :count, :limit, keyword_init: true) do
      def prev = page > 1 ? page - 1 : nil
      def next = page < pages ? page + 1 : nil
    end

    included do
      include Pagy::Backend if defined?(Pagy::Backend)
    end

    private

    # Applies q= text search (escaped, parameter-bound), boolean filters and a
    # created-date range to +scope+. Malformed values never raise: bad dates
    # and unknown boolean values silently skip their filter.
    def llama_filtered_scope(scope, search_columns: [], boolean_columns: [], date_column: :created_at)
      q = params[:q].to_s.strip
      if q.present? && search_columns.any?
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(q)}%"
        # Explicit ESCAPE so the sanitized backslashes work on SQLite too,
        # not just PostgreSQL.
        arel = search_columns
          .map { |column| scope.klass.arel_table[column].matches(pattern, "\\") }
          .inject(:or)
        scope = scope.where(arel)
      end

      boolean_columns.each do |column|
        value = params[column]
        scope = scope.where(column => value == "true") if %w[true false].include?(value)
      end

      if date_column
        if (from = llama_parse_date(params[:from]))
          scope = scope.where(date_column => from.beginning_of_day..)
        end
        if (to = llama_parse_date(params[:to]))
          scope = scope.where(date_column => ..to.end_of_day)
        end
      end

      scope
    end

    def llama_parse_date(value)
      Date.iso8601(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    # Returns [pagination, records]. Uses Pagy when the host has it; otherwise
    # a minimal offset fallback. Page size is clamped to MAX_PER_PAGE and
    # out-of-range pages never 500.
    def llama_paginate(scope)
      limit = params[:per_page].to_i
      limit = DEFAULT_PER_PAGE unless limit.positive?
      limit = [limit, MAX_PER_PAGE].min
      page = [params[:page].to_i, 1].max

      if respond_to?(:pagy, true)
        begin
          pagy(scope, limit: limit, page: page)
        rescue Pagy::OverflowError
          pagy(scope, limit: limit, page: 1)
        end
      else
        count = scope.count
        pages = [(count.to_f / limit).ceil, 1].max
        page = [page, pages].min
        records = scope.offset((page - 1) * limit).limit(limit)
        [Page.new(page: page, pages: pages, count: count, limit: limit), records]
      end
    end

    # After a successful create/update from inside the record drawer, refresh
    # the whole page: the index re-GETs its current URL (filters and page kept)
    # so the table is never stale, and the drawer closes with it. Outside a
    # frame this is a normal redirect.
    def llama_after_save_redirect(record, notice:)
      flash[:notice] = notice
      if turbo_frame_request?
        # request_id: nil is required — the default stamps this request's id,
        # which the submitting client ignores (Turbo's own-echo debounce).
        # The content type must be forced because this renders from the
        # negotiated format.html branch.
        render turbo_stream: turbo_stream.refresh(request_id: nil),
               content_type: "text/vnd.turbo-stream.html"
      else
        redirect_to record, status: :see_other
      end
    end
  end
end
