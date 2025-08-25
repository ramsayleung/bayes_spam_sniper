class AddGroupNameToBannedUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :banned_users, :group_name, :string
  end
end
