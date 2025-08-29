class AddMessageIdToTrainedMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :trained_messages, :message_id, :integer, default: 0, null: false
  end
end
