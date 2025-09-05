class AddMessageHashToTrainedMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :trained_messages, :message_hash, :string, limit: 64 # 64-character limit is sufficient for SHA256 hex output
    add_index :trained_messages, :message_hash  end
end
