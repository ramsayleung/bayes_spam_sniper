class CreateTrainedMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :trained_messages do |t|
      t.integer :group_id
      t.text :message
      t.integer :message_type
      t.integer :sender_chat_id

      t.timestamps
    end
    add_index :trained_messages, :group_id
    add_index :trained_messages, :sender_chat_id
  end
end
