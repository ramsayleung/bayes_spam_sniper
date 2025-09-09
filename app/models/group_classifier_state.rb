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
end
