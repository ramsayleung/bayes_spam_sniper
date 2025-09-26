class AddSourceToTrainedMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :trained_messages, :source, :integer, default: 0, null: false
  end
end
