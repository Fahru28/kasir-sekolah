module LlamaBotRails
  module TicketsHelper
    def render_markdown(text)
      return "" if text.blank?

      lines = text.split("\n")
      html_parts = []
      current_list = []
      current_blockquote = []
      current_table = []
      current_code_block = []
      in_list = false
      in_blockquote = false
      in_table = false
      in_code_block = false
      code_language = nil

      lines.each do |line|
        # Handle code blocks (triple backticks)
        if line.strip.start_with?('```')
          if in_code_block
            # Closing code block
            html_parts << render_code_block(current_code_block, code_language)
            current_code_block = []
            in_code_block = false
            code_language = nil
          else
            # Opening code block
            if in_list
              html_parts << render_list(current_list)
              current_list = []
              in_list = false
            end
            if in_blockquote
              html_parts << render_blockquote(current_blockquote)
              current_blockquote = []
              in_blockquote = false
            end
            if in_table
              html_parts << render_table(current_table)
              current_table = []
              in_table = false
            end
            in_code_block = true
            code_language = line.strip.sub('```', '').strip
            code_language = nil if code_language.empty?
          end
          next
        end

        # If inside code block, collect lines
        if in_code_block
          current_code_block << line
          next
        end

        # Handle tables (lines containing pipes |)
        if line.strip.start_with?('|') && line.strip.end_with?('|')
          if in_list
            html_parts << render_list(current_list)
            current_list = []
            in_list = false
          end
          if in_blockquote
            html_parts << render_blockquote(current_blockquote)
            current_blockquote = []
            in_blockquote = false
          end
          in_table = true
          current_table << line
        elsif in_table && line.strip.empty?
          # End table on empty line
          html_parts << render_table(current_table)
          current_table = []
          in_table = false
        elsif in_table && !(line.strip.start_with?('|') && line.strip.end_with?('|'))
          # End table when non-table line appears
          html_parts << render_table(current_table)
          current_table = []
          in_table = false
        end

        # Handle blockquotes (lines starting with >)
        if line.strip.start_with?('>')
          if in_list
            html_parts << render_list(current_list)
            current_list = []
            in_list = false
          end
          if in_table
            html_parts << render_table(current_table)
            current_table = []
            in_table = false
          end
          in_blockquote = true
          quote_text = line.sub(/^>\s*/, '')
          current_blockquote << quote_text
        elsif in_blockquote && line.strip.empty?
          # End blockquote on empty line
          html_parts << render_blockquote(current_blockquote)
          current_blockquote = []
          in_blockquote = false
        elsif in_blockquote && !line.strip.start_with?('>')
          # End blockquote when non-quote line appears
          html_parts << render_blockquote(current_blockquote)
          current_blockquote = []
          in_blockquote = false
        end

        # Handle list items (lines starting with -, *, or digits.)
        if line.strip.match?(/^[-*]\s+/) || line.strip.match?(/^\d+\.\s+/)
          in_list = true
          if in_blockquote
            html_parts << render_blockquote(current_blockquote)
            current_blockquote = []
            in_blockquote = false
          end
          if in_table
            html_parts << render_table(current_table)
            current_table = []
            in_table = false
          end
          current_list << line
        elsif in_list && line.strip.empty?
          # Empty line might end list
          html_parts << render_list(current_list)
          current_list = []
          in_list = false
        elsif in_list && !line.strip.match?(/^[-*]\s+/) && !line.strip.match?(/^\d+\.\s+/)
          # Non-list line ends list
          html_parts << render_list(current_list)
          current_list = []
          in_list = false
        end

        # Handle horizontal rules
        if line.strip == '---' || line.strip == '***' || line.strip == '___'
          html_parts << '<hr class="my-6 border-t-2 border-gray-300">'
        # Handle headings
        elsif line.strip.match?(/^### /)
          html_parts << line.gsub(/^### (.*?)$/, '<h3 class="text-lg font-bold mt-4 mb-2">\1</h3>')
        elsif line.strip.match?(/^## /)
          html_parts << line.gsub(/^## (.*?)$/, '<h2 class="text-xl font-bold mt-5 mb-3">\1</h2>')
        elsif line.strip.match?(/^# /)
          html_parts << line.gsub(/^# (.*?)$/, '<h1 class="text-2xl font-bold mt-6 mb-3">\1</h1>')
        # Handle regular paragraphs
        elsif line.strip.length > 0 && !in_list && !in_blockquote && !in_table && !line.strip.match?(/^(#|##|###|---|---|\*\*\*)/)
          html_parts << "<p class=\"mt-3\">#{format_inline(line)}</p>"
        end
      end

      # Close any remaining list, blockquote, table, or code block
      html_parts << render_list(current_list) if in_list && current_list.any?
      html_parts << render_blockquote(current_blockquote) if in_blockquote && current_blockquote.any?
      html_parts << render_table(current_table) if in_table && current_table.any?
      html_parts << render_code_block(current_code_block, code_language) if in_code_block && current_code_block.any?

      html_parts.join("\n").html_safe
    end

    def status_badge_class(status)
      case status
      when 'backlog'
        'badge-neutral'
      when 'assigned'
        'badge-info'
      when 'in_progress'
        'badge-warning'
      when 'review'
        'badge-secondary'
      when 'incomplete'
        'badge-error'
      when 'done'
        'badge-success'
      else
        'badge-ghost'
      end
    end

    def status_column_gradient(status)
      case status
      when 'backlog'
        'from-slate-500 to-slate-600'
      when 'assigned'
        'from-blue-500 to-blue-600'
      when 'in_progress'
        'from-amber-500 to-amber-600'
      when 'review'
        'from-purple-500 to-purple-600'
      when 'incomplete'
        'from-red-500 to-red-600'
      when 'done'
        'from-green-500 to-green-600'
      else
        'from-gray-500 to-gray-600'
      end
    end

    def status_icon(status)
      case status
      when 'backlog'
        'fa-inbox'
      when 'assigned'
        'fa-user-check'
      when 'in_progress'
        'fa-spinner'
      when 'review'
        'fa-eye'
      when 'incomplete'
        'fa-exclamation-triangle'
      when 'done'
        'fa-check-circle'
      else
        'fa-question'
      end
    end

    private

    def format_inline(text)
      # 1. Escape HTML to prevent XSS
      escaped = ERB::Util.html_escape(text)

      # 2. Add auto-linking
      url_pattern = /(https?:\/\/[^\s<]+[^.,\s<])/
      linked_text = escaped.gsub(url_pattern) do |url|
        "<a href='#{url}' target='_blank' class='text-blue-600 underline hover:text-blue-800'>#{url}</a>"
      end

      linked_text
        .gsub(/`(.*?)`/, '<code class="bg-gray-200 px-2 py-1 rounded font-mono text-sm">\1</code>')
        .gsub(/\*\*(.*?)\*\*/, '<strong class="font-bold">\1</strong>')
        .gsub(/__(.*?)__/, '<strong class="font-bold">\1</strong>')
        .gsub(/\*(.*?)\*/, '<em class="italic">\1</em>')
    end

    def render_list(lines)
      return "" if lines.empty?

      list_html = '<ul class="list-disc ml-4 my-2">'
      lines.each do |line|
        item_text = line.strip.sub(/^[-*]\s+/, '').sub(/^\d+\.\s+/, '')
        list_html += "<li class=\"ml-4\">#{format_inline(item_text)}</li>"
      end
      list_html += '</ul>'
      list_html
    end

    def render_blockquote(lines)
      return "" if lines.empty?

      quote_html = '<div class="bg-blue-50 border-l-4 border-blue-300 pl-4 py-2 my-3">'
      lines.each do |line|
        clean_line = line.strip.sub(/^>\s*/, '')
        quote_html += "<p class=\"text-sm text-gray-700\">#{format_inline(clean_line)}</p>" if clean_line.present?
      end
      quote_html += '</div>'
      quote_html
    end

    def render_table(lines)
      return "" if lines.empty?

      # Parse table rows
      rows = lines.map do |line|
        line.strip.split('|').map(&:strip).reject(&:empty?)
      end

      return "" if rows.empty?

      # First row is header, skip separator row (all dashes)
      header_row = rows[0]
      data_rows = rows.reject { |row| row.all? { |cell| cell.match?(/^-+$/) } }[1..-1] || []

      table_html = '<div class="overflow-x-auto my-4"><table class="table table-compact w-full"><thead>'

      # Render header
      table_html += '<tr>'
      header_row.each do |cell|
        table_html += "<th class=\"bg-gray-100 font-bold text-left\">#{format_inline(cell)}</th>"
      end
      table_html += '</tr></thead><tbody>'

      # Render data rows with alternating colors
      data_rows.each_with_index do |row, index|
        row_class = index.even? ? 'bg-white' : 'bg-gray-50'
        table_html += "<tr class=\"#{row_class} hover:bg-gray-100 transition-colors\">"
        row.each do |cell|
          table_html += "<td class=\"border-t py-2 px-3\">#{format_inline(cell)}</td>"
        end
        table_html += '</tr>'
      end

      table_html += '</tbody></table></div>'
      table_html
    end

    def render_code_block(lines, language = nil)
      return "" if lines.empty?

      code_content = lines.join("\n")
      escaped_code = ERB::Util.html_escape(code_content)

      language_label = language ? "<span class=\"text-xs text-gray-500 font-semibold\">#{language.upcase}</span>" : ""

      code_html = '<div class="my-4 bg-gray-900 rounded-lg overflow-hidden">'
      code_html += "<div class=\"bg-gray-800 px-4 py-2 border-b border-gray-700\">#{language_label}</div>" if language_label.present?
      code_html += "<pre class=\"p-4 text-sm text-gray-100 font-mono overflow-x-auto\"><code>#{escaped_code}</code></pre>"
      code_html += '</div>'

      code_html
    end
  end
end
