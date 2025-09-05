class TrainedMessage < ApplicationRecord
  enum :message_type, { spam: 0, ham: 1, untrained: 2 }
  # New enum for what is being trained
  enum :training_target, { message_content: 0, user_name: 1 }
  module MessageType
    SPAM = "spam"
    HAM = "ham"
    UNTRAINED = "untrained"
  end
  module TrainingTarget
    MESSAGE_CONTENT = "message_content"
    USER_NAME = "user_name"
  end
  GLOBAL_SHARED_MESSAGE = 0

  scope :shared, -> { where(group_id: GLOBAL_SHARED_MESSAGE) }
  scope :trainable, -> { where(message_type: [ :spam, :ham ]) }
  scope :for_message_content, -> { where(training_target: :message_content) }
  scope :for_user_name, -> { where(training_target: :user_name) }

  validates :group_id, presence: true
  validates :message, presence: true
  validates :message_type, presence: true

  before_save :set_message_hash
  # Automatically train classifier after creating/updating a message
  after_create :retrain_classifier, if: :trainable?
  after_update :retrain_classifier, if: :trainable_type_changed?
  after_destroy :retrain_classifier, if: :trainable?
  after_create :should_ban_user, if: :trainable?
  after_update :should_ban_user, if: :trainable_type_changed?


  def should_ban_user
    spam_ban_threshold = Rails.application.config.spam_ban_threshold
    spam_count = TrainedMessage.where(group_id: self.group_id, sender_chat_id: self.sender_chat_id, message_type: :spam).count
    if spam_count >= spam_ban_threshold
      Rails.logger.info "user: #{self.sender_user_name} sent more than 3 spam messages in group: #{self.group_id}, ban this user from group"
      TelegramPostWorkerJob.perform_later(
        action: TelegramPostWorkerJob::PostAction::BAN_USER,
        trained_message: self
      )
    end
  end
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
    (old_type != "untrained") || (new_type != "untrained")
  end

  def set_message_hash
    self.message_hash = Digest::SHA256.hexdigest(message.to_s)
  end
end
