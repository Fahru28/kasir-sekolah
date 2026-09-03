module LlamaBotRails
  # One styled pagination nav for every list page in the fleet.
  #
  # Hand-written index views used to either copy the scaffold's nav markup or
  # call Pagy's own +pagy_nav+, which renders unstyled markup that looks broken
  # on a Tailwind page. This helper is the default both paths land on:
  # `llama_pagination_nav(@pagy)` in a view, and +pagy_nav+ itself via
  # LlamaBotRails::PagyNavOverride.
  #
  # Works with a real Pagy object and with ScaffoldFiltering::Page (the no-Pagy
  # fallback) — it only reads page/pages/count/prev/next.
  module PaginationHelper
    # Page numbers shown on each side of the current page before gapping.
    PAGINATION_WINDOW = 2

    LINK_CLASSES = "rounded-md border border-gray-300 bg-white px-3 py-2 text-sm text-gray-700 hover:bg-gray-50".freeze
    CURRENT_CLASSES = "rounded-md border border-blue-600 bg-blue-600 px-3 py-2 text-sm font-medium text-white".freeze
    GAP_CLASSES = "px-2 py-2 text-sm text-gray-400".freeze

    # Renders nothing when there is nothing to page through, so views can call
    # it unconditionally. Extra keyword args (Pagy passes id:, aria_label:, ...)
    # are accepted and ignored so this can stand in for +pagy_nav+.
    def llama_pagination_nav(pagy, label: "total", aria_label: "Pagination", **_pagy_options)
      return if pagy.nil? || pagy.pages.to_i <= 1

      tag.nav(class: "mt-4 flex flex-wrap items-center justify-between gap-2", aria: { label: aria_label }) do
        safe_join([ llama_pagination_summary(pagy, label: label), llama_pagination_links(pagy) ])
      end
    end

    # "Page 2 of 7 · 168 total" — the count half is dropped for countless mode.
    def llama_pagination_summary(pagy, label: "total")
      text = "Page #{pagy.page} of #{pagy.pages}"
      count = pagy.count if pagy.respond_to?(:count)
      text = "#{text} · #{number_with_delimiter(count)} #{label}" if count

      tag.p(text, class: "text-sm text-gray-600")
    end

    # The page window: 1 … 4 [5] 6 … 20, with prev/next on the ends.
    def llama_pagination_series(page, pages, window: PAGINATION_WINDOW)
      wanted = ([ 1, pages ] + ((page - window)..(page + window)).to_a)
        .select { |n| n >= 1 && n <= pages }
        .uniq
        .sort

      wanted.each_with_object([]) do |number, series|
        series << :gap if series.last.is_a?(Integer) && number > series.last + 1
        series << number
      end
    end

    # Keeps every other query param (filters, per_page, sort) on the link.
    def llama_pagination_url(page)
      query = request.query_parameters.merge("page" => page)
      "#{request.path}?#{query.to_query}"
    end

    private

    def llama_pagination_links(pagy)
      links = []
      links << link_to("Previous", llama_pagination_url(pagy.prev), class: LINK_CLASSES, rel: "prev") if pagy.prev

      llama_pagination_series(pagy.page.to_i, pagy.pages.to_i).each do |number|
        links << if number == :gap
          tag.span("…", class: GAP_CLASSES)
        elsif number == pagy.page.to_i
          tag.span(number, class: CURRENT_CLASSES, aria: { current: "page" })
        else
          link_to(number, llama_pagination_url(number), class: LINK_CLASSES)
        end
      end

      links << link_to("Next", llama_pagination_url(pagy.next), class: LINK_CLASSES, rel: "next") if pagy.next

      tag.div(safe_join(links), class: "flex flex-wrap items-center gap-2")
    end
  end
end
