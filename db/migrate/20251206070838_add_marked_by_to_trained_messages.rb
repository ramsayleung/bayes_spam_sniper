class AddMarkedByToTrainedMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :trained_messages, :marked_by, :integer, default: 0, null: false
  end
end
