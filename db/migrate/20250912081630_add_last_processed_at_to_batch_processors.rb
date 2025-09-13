class AddLastProcessedAtToBatchProcessors < ActiveRecord::Migration[8.0]
  def change
    add_column :batch_processors, :last_processed_at, :datetime
  end
end
