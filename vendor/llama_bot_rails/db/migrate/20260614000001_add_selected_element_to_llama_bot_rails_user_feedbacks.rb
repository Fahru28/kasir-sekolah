class AddSelectedElementToLlamaBotRailsUserFeedbacks < ActiveRecord::Migration[7.2]
  def change
    add_column :llama_bot_rails_user_feedbacks, :selected_element_html, :text
    add_column :llama_bot_rails_user_feedbacks, :selected_element_selector, :string
    add_column :llama_bot_rails_user_feedbacks, :selected_element_url, :string
  end
end
