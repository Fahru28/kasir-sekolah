class AddResearchNotesToLlamaBotRailsTickets < ActiveRecord::Migration[7.2]
  def change
    # Guard: create_llama_bot_rails_tickets already defines research_notes, so a
    # fresh `db:migrate` from zero would otherwise collide (duplicate column).
    add_column :llama_bot_rails_tickets, :research_notes, :text unless column_exists?(:llama_bot_rails_tickets, :research_notes)
  end
end
