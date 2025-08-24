class AddSpamMessageToBannedUser < ActiveRecord::Migration[8.0]
  def change
    add_column :banned_users, :spam_message, :text
  end
end
