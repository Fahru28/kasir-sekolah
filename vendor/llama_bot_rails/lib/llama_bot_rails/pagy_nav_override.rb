module LlamaBotRails
  # Makes Pagy's own +pagy_nav+ render the styled LlamaPress nav.
  #
  # Apps include Pagy::Frontend in ApplicationHelper, so any view (or agent) that
  # reaches for pagy_nav got Pagy's raw markup — unstyled links on a Tailwind
  # page. Prepending onto Pagy::Frontend wins regardless of helper include order,
  # which a plain helper method could not guarantee.
  #
  # Falls back to Pagy's nav if the LlamaPress helper is not in the view (e.g. a
  # mailer or a host that skipped the engine helpers), and can be turned off with
  # `config.llama_bot_rails.styled_pagy_nav = false`.
  module PagyNavOverride
    def pagy_nav(pagy, **options)
      return super unless respond_to?(:llama_pagination_nav)

      llama_pagination_nav(pagy, **options)
    end
  end
end
