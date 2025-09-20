class ChangeTelegramIdsToBigint < ActiveRecord::Migration[8.0]
  def change
    # Update banned_users table
    change_column :banned_users, :group_id, :bigint
    change_column :banned_users, :sender_chat_id, :bigint

    # Update group_classifier_states table
    change_column :group_classifier_states, :group_id, :bigint

    # Update trained_messages table
    change_column :trained_messages, :group_id, :bigint
    change_column :trained_messages, :sender_chat_id, :bigint
  end
end
