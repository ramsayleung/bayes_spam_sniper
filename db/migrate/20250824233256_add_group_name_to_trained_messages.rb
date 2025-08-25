class AddGroupNameToTrainedMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :trained_messages, :group_name, :string
  end
end
