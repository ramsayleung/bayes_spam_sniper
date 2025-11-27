class GroupClassifierState < ApplicationRecord
  # Automatically convert the text column to a Hash when loaded,
  # and back to a JSON string when saved.
  serialize :spam_counts, coder: JSON
  serialize :ham_counts, coder: JSON

  TELEGRAM_DATA_COLLECTOR_GROUP_ID = -1
  TELEGRAM_DATA_COLLECTOR_GROUP_NAME = "Telegram Data Collector Group"
  USER_NAME_CLASSIFIER_GROUP_ID = 0
  USER_NAME_CLASSIFIER_GROUP_NAME = "User Name Classifier"
  scope :username, -> { where(group_id: USER_NAME_CLASSIFIER_GROUP_ID) }
  # private chat is positive id, group/channel chat is negative id
  # find all classifiers for public, including group and username
  scope :for_public, -> { where(arel_table[:group_id].lteq(0)) }
  scope :for_group, -> { where("group_id < 0") }

  validates :group_id, uniqueness: true
  validates :language, inclusion: { in: I18n.available_locales.map(&:to_s) }, allow_nil: true

  # Get top N most frequent spam words
  def top_spam_words(limit = 50)
    return [] unless spam_counts.is_a?(Hash)
    spam_counts.to_a.sort_by { |word, count| -count }.first(limit)
  end

  # Get top N most frequent ham words
  def top_ham_words(limit = 50)
    return [] unless ham_counts.is_a?(Hash)
    ham_counts.to_a.sort_by { |word, count| -count }.first(limit)
  end

  # Get total spam word count
  def total_spam_words_count
    return 0 unless spam_counts.is_a?(Hash)
    spam_counts.values.sum
  end

  # Get total ham word count
  def total_ham_words_count
    return 0 unless ham_counts.is_a?(Hash)
    ham_counts.values.sum
  end

  # Get configurable K value from parameter or use default
  def get_k_value(params_k)
    k = params_k.present? ? params_k.to_i : 20
    k = 50 if k > 50  # Cap at 50 to prevent performance issues
    k = 5 if k < 5     # Minimum of 5
    k
  end
end
