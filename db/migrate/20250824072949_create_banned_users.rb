class CreateBannedUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :banned_users do |t|
      t.integer :group_id
      t.integer :sender_chat_id
      t.string :sender_user_name

      t.timestamps
    end
  end
end
