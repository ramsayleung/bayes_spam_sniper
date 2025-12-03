class SetDefaultValuesForGroupClassifierStateColumns < ActiveRecord::Migration[8.1]
  def up
    # Set default values for existing records that might have NULL values
    execute <<-SQL
      UPDATE group_classifier_states
      SET total_spam_words = COALESCE(total_spam_words, 0),
          total_ham_words = COALESCE(total_ham_words, 0),
          total_spam_messages = COALESCE(total_spam_messages, 0),
          total_ham_messages = COALESCE(total_ham_messages, 0),
          vocabulary_size = COALESCE(vocabulary_size, 0),
          spam_counts = COALESCE(spam_counts, '{}'),
          ham_counts = COALESCE(ham_counts, '{}')
    SQL

    # Change the column defaults
    change_column_default :group_classifier_states, :total_spam_words, 0
    change_column_default :group_classifier_states, :total_ham_words, 0
    change_column_default :group_classifier_states, :total_spam_messages, 0
    change_column_default :group_classifier_states, :total_ham_messages, 0
    change_column_default :group_classifier_states, :vocabulary_size, 0
    change_column_default :group_classifier_states, :spam_counts, '{}'
    change_column_default :group_classifier_states, :ham_counts, '{}'
  end

  def down
    # Revert the column defaults
    change_column_default :group_classifier_states, :total_spam_words, nil
    change_column_default :group_classifier_states, :total_ham_words, nil
    change_column_default :group_classifier_states, :total_spam_messages, nil
    change_column_default :group_classifier_states, :total_ham_messages, nil
    change_column_default :group_classifier_states, :vocabulary_size, nil
    change_column_default :group_classifier_states, :spam_counts, nil
    change_column_default :group_classifier_states, :ham_counts, nil

    # Reset values back to NULL where they were 0
    execute <<-SQL
      UPDATE group_classifier_states
      SET total_spam_words = NULL WHERE total_spam_words = 0,
          total_ham_words = NULL WHERE total_ham_words = 0,
          total_spam_messages = NULL WHERE total_spam_messages = 0,
          total_ham_messages = NULL WHERE total_ham_messages = 0,
          vocabulary_size = NULL WHERE vocabulary_size = 0,
          spam_counts = NULL WHERE spam_counts = '{}',
          ham_counts = NULL WHERE ham_counts = '{}'
    SQL
  end
end
