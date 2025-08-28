class TrainedMessage < ApplicationRecord
  enum :message_type, { spam: 0, ham: 1 , untrained: 2}
  # New enum for what is being trained
  enum :training_target, { message_content: 0, user_name: 1 }
  GLOBAL_SHARED_MESSAGE = 0
  scope :shared, -> { where(group_id: GLOBAL_SHARED_MESSAGE) }
  scope :trainable, -> { where(message_type: [:spam, :ham]) }
  scope :for_message_content, -> {where(training_target: :message_content)}
  scope :for_user_name, -> {where(training_target: :user_name)}

  validates :group_id, presence: true
  validates :message, presence: true
  validates :message_type, presence: true
  
  # Automatically train classifier after creating/updating a message
  after_create :retrain_classifier, if: :trainable?
  after_update :retrain_classifier, if: :trainable_type_changed?
  after_destroy :retrain_classifier, if: :trainable?

  def retrain_classifier
    return if untrained?

    if user_name?
      # Target is user_name
      ClassifierTrainerJob.perform_later(GroupClassifierState::USER_NAME_CLASSIFIER_GROUP_ID, GroupClassifierState::USER_NAME_CLASSIFIER_GROUP_NAME)
    else
      # For efficiency, we could queue this as a background job
      ClassifierTrainerJob.perform_later(group_id, group_name)
    end
  end

  private

  def trainable?
    spam? || ham?
  end

  def trainable_type_changed?
    return false unless saved_change_to_message_type?

    old_type, new_type = saved_change_to_message_type
    (old_type != 'untrained') || (new_type != 'untrained')
  end
end
