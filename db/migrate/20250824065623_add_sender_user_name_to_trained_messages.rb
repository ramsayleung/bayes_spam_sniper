class AddSenderUserNameToTrainedMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :trained_messages, :sender_user_name, :string
  end
end
