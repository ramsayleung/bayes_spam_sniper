class AddMessageIdToBannedUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :banned_users, :message_id, :integer, default: 0, null: false
  end
end
