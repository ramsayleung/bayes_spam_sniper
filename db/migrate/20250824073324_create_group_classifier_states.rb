class CreateGroupClassifierStates < ActiveRecord::Migration[8.0]
  def change
    create_table :group_classifier_states do |t|
      t.integer :group_id
      t.text :spam_counts
      t.text :ham_counts
      t.integer :total_spam_words
      t.integer :total_ham_words
      t.integer :total_spam_messages
      t.integer :total_ham_messages
      t.integer :vocabulary_size

      t.timestamps
    end
    add_index :group_classifier_states, :group_id
  end
end
