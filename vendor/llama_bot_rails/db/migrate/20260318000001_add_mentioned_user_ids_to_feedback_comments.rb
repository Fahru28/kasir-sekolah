class AddMentionedUserIdsToFeedbackComments < ActiveRecord::Migration[7.2]
  def change
    add_column :llama_bot_rails_feedback_comments, :mentioned_user_ids, :json, default: []
  end
end
