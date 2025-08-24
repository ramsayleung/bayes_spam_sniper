json.extract! group_classifier_state, :id, :group_id, :spam_counts, :ham_counts, :total_spam_words, :total_ham_words, :total_spam_messages, :total_ham_messages, :vocabulary_size, :created_at, :updated_at
json.url group_classifier_state_url(group_classifier_state, format: :json)
