module LlamaBotRails
  module FeedbackHelper
    # Ceiling on the captured markup we'll render into the live preview frame. The user
    # can point the element selector at anything — including <body> — and dropping a
    # megabyte of markup into a srcdoc attribute bloats the dashboard page itself.
    # Past this we show the source only.
    SELECTED_ELEMENT_PREVIEW_LIMIT = 100_000

    def selected_element_preview_too_large?(html)
      html.to_s.bytesize > SELECTED_ELEMENT_PREVIEW_LIMIT
    end

    # Wraps the captured element in a minimal document that pulls in the same CSS the
    # dashboard itself uses, so a Tailwind/daisyUI element looks roughly like it did on
    # the page it came from. Two things keep the captured markup from touching this page:
    # every <script> in the capture is dropped here, and the view renders the frame with
    # sandbox="allow-scripts" (deliberately WITHOUT allow-same-origin), so what's left
    # runs in an opaque origin with no reach into the dashboard's DOM, cookies or storage.
    # allow-scripts is needed because the Tailwind CDN below is itself a script.
    def selected_element_preview_document(html)
      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <script src="https://cdn.tailwindcss.com"></script>
          <link href="https://cdn.jsdelivr.net/npm/daisyui@4.4.19/dist/full.min.css" rel="stylesheet" type="text/css" />
          <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css" />
          <style>body { margin: 0; padding: 12px; background: #ffffff; }</style>
        </head>
        <body>#{strip_scripts(html)}</body>
        </html>
      HTML
    end

    # The page the feedback was reported on, as an in-app path. When an element was
    # picked, the path carries its selector so feedback_element_highlight.js can scroll
    # to and ring that element on arrival — landing on the right page still left you
    # guessing WHICH element the report was about.
    #
    # Only same-app relative paths are linkable: the value is captured client-side, and
    # a "//evil.example" or "javascript:" value would otherwise turn this dashboard into
    # an open redirect. Anything else returns nil and the view shows no link.
    def feedback_page_path(feedback)
      path = feedback.selected_element_url.to_s.strip
      return nil unless path.start_with?('/')
      return nil if path.start_with?('//')

      uri = begin
        URI.parse(path)
      rescue URI::InvalidURIError
        return nil
      end
      return path if feedback.selected_element_selector.blank?

      query = URI.decode_www_form(uri.query.to_s)
      query.reject! { |key, _| %w[lp_feedback_element lp_feedback_id].include?(key) }
      query << ['lp_feedback_element', feedback.selected_element_selector]
      query << ['lp_feedback_id', feedback.id.to_s] if feedback.id
      uri.query = URI.encode_www_form(query)
      uri.to_s
    end

    # A short human name for the picked element ("<button> Save changes") for the panel
    # heading — the raw CSS selector alone reads as noise to a non-developer.
    def selected_element_label(feedback)
      html = feedback.selected_element_html.to_s
      tag = html[/\A\s*<\s*([a-zA-Z][\w-]*)/, 1]
      text = strip_scripts(html).gsub(/<[^>]*>/, ' ').squish

      return nil if tag.blank? && text.blank?

      name = tag.present? ? "<#{tag.downcase}>" : nil
      [name, text.presence && truncate(text, length: 60)].compact.join(' ')
    end

    def feedback_status_badge_class(status)
      case status
      when 'open' then 'badge-warning'
      when 'under_review' then 'badge-info'
      when 'acknowledged' then 'badge-primary'
      when 'in_progress' then 'badge-accent'
      when 'resolved' then 'badge-success'
      when 'closed' then 'badge-neutral'
      else 'badge-ghost'
      end
    end

    def feedback_status_icon(status)
      case status
      when 'open' then 'fa-circle-exclamation'
      when 'under_review' then 'fa-magnifying-glass'
      when 'acknowledged' then 'fa-check'
      when 'in_progress' then 'fa-spinner'
      when 'resolved' then 'fa-circle-check'
      when 'closed' then 'fa-lock'
      else 'fa-question'
      end
    end

    def feedback_type_icon(type)
      case type
      when 'bug' then 'fa-bug'
      when 'suggestion' then 'fa-lightbulb'
      when 'question' then 'fa-circle-question'
      when 'complaint' then 'fa-triangle-exclamation'
      when 'praise' then 'fa-star'
      else 'fa-comment'
      end
    end

    def feedback_type_badge_class(type)
      case type
      when 'bug' then 'badge-error'
      when 'suggestion' then 'badge-info'
      when 'question' then 'badge-warning'
      when 'complaint' then 'badge-error'
      when 'praise' then 'badge-success'
      else 'badge-ghost'
      end
    end

    def request_status_badge_class(status)
      case status
      when 'submitted' then 'badge-info'
      when 'under_review' then 'badge-warning'
      when 'planned' then 'badge-primary'
      when 'in_progress' then 'badge-accent'
      when 'completed' then 'badge-success'
      when 'declined' then 'badge-error'
      else 'badge-ghost'
      end
    end

    def request_status_icon(status)
      case status
      when 'submitted' then 'fa-paper-plane'
      when 'under_review' then 'fa-magnifying-glass'
      when 'planned' then 'fa-calendar'
      when 'in_progress' then 'fa-spinner'
      when 'completed' then 'fa-circle-check'
      when 'declined' then 'fa-xmark'
      else 'fa-question'
      end
    end

    def request_type_icon(type)
      case type
      when 'feature' then 'fa-plus'
      when 'enhancement' then 'fa-arrow-up'
      when 'integration' then 'fa-plug'
      when 'content' then 'fa-file-lines'
      else 'fa-clipboard'
      end
    end

    def priority_badge_class(priority)
      case priority.to_i
      when 0 then 'badge-ghost'
      when 1 then 'badge-info'
      when 2 then 'badge-warning'
      when 3 then 'badge-error'
      else 'badge-ghost'
      end
    end

    def priority_label(priority)
      case priority.to_i
      when 0 then 'Low'
      when 1 then 'Medium'
      when 2 then 'High'
      when 3 then 'Critical'
      else 'Unknown'
      end
    end

    def attachment_icon(content_type)
      case content_type
      when /^image/ then 'fa-image'
      when /^video/ then 'fa-video'
      when /pdf/ then 'fa-file-pdf'
      when /word|document/ then 'fa-file-word'
      when /excel|spreadsheet/ then 'fa-file-excel'
      when /zip|archive/ then 'fa-file-zipper'
      when /text/ then 'fa-file-lines'
      else 'fa-file'
      end
    end

    def tag_style(tag)
      "background-color: #{tag.color}; color: #{contrasting_text_color(tag.color)}"
    end

    def highlight_mentions(text)
      return '' if text.blank?

      # Match @mentions (email-like patterns after @)
      highlighted = ERB::Util.html_escape(text).gsub(/@[\w@.+-]+/) do |match|
        "<span class=\"text-blue-600 font-semibold\">#{match}</span>"
      end
      highlighted.html_safe
    end

    private

    def strip_scripts(html)
      html.to_s
          .gsub(%r{<script\b[^>]*>.*?</script>}mi, '')
          .gsub(%r{<script\b[^>]*/?>}mi, '')
    end

    def contrasting_text_color(hex_color)
      # Convert hex to RGB and calculate luminance
      hex = hex_color.gsub('#', '')
      r = hex[0..1].to_i(16)
      g = hex[2..3].to_i(16)
      b = hex[4..5].to_i(16)
      luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255
      luminance > 0.5 ? '#000000' : '#ffffff'
    end
  end
end
