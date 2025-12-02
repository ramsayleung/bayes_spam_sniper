class SetDefaultValuesForGroupClassifierStateColumns < ActiveRecord::Migration[8.1]
  def up
    # Set default values for existing records that might have NULL values
    execute <<-SQL
      UPDATE group_classifier_states
      SET total_spam_words = COALESCE(total_spam_words, 0),
          total_ham_words = COALESCE(total_ham_words, 0),
          total_spam_messages = COALESCE(total_spam_messages, 0),
          total_ham_messages = COALESCE(total_ham_messages, 0),
          vocabulary_size = COALESCE(vocabulary_size, 0)
    SQL

    # Change the column defaults
    change_column_default :group_classifier_states, :total_spam_words, 0
    change_column_default :group_classifier_states, :total_ham_words, 0
    change_column_default :group_classifier_states, :total_spam_messages, 0
    change_column_default :group_classifier_states, :total_ham_messages, 0
    change_column_default :group_classifier_states, :vocabulary_size, 0
  end

  def down
    # Revert the column defaults
    change_column_default :group_classifier_states, :total_spam_words, nil
    change_column_default :group_classifier_states, :total_ham_words, nil
    change_column_default :group_classifier_states, :total_spam_messages, nil
    change_column_default :group_classifier_states, :total_ham_messages, nil
    change_column_default :group_classifier_states, :vocabulary_size, nil

    # Reset values back to NULL where they were 0
    execute <<-SQL
      UPDATE group_classifier_states
      SET total_spam_words = NULL WHERE total_spam_words = 0,
          total_ham_words = NULL WHERE total_ham_words = 0,
          total_spam_messages = NULL WHERE total_spam_messages = 0,
          total_ham_messages = NULL WHERE total_ham_messages = 0,
          vocabulary_size = NULL WHERE vocabulary_size = 0
    SQL
  end
end
