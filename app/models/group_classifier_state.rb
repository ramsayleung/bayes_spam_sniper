class GroupClassifierState < ApplicationRecord
  # Automatically convert the text column to a Hash when loaded,
  # and back to a JSON string when saved.
  serialize :spam_counts, coder: JSON
  serialize :ham_counts, coder: JSON
end
