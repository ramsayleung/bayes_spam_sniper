class CreateBatchProcessors < ActiveRecord::Migration[8.0]
  def change
    create_table :batch_processors do |t|
      t.string :batch_key, null: false
      t.string :job_class, null: false
      t.text :shared_args_json, default: "{}"
      t.text :pending_items_json, default: "[]"
      t.integer :pending_count, default: 0
      t.integer :batch_size, default: 100
      t.integer :batch_window_in_seconds, default: 30

      t.timestamps
    end
    add_index :batch_processors, :batch_key, unique: true
    add_index :batch_processors, :updated_at
  end
end
