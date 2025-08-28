class AddTrainingTargetToTrainedMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :trained_messages, :training_target, :integer, default: 0, null: false
  end
end
