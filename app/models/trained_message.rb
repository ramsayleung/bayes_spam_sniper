class TrainedMessage < ApplicationRecord
  enum :message_type, { spam: 0, ham: 1, untrained: 2, maybe_spam: 3, maybe_ham: 4 }
  # New enum for what is being trained
  enum :training_target, { message_content: 0, user_name: 1 }
  module MessageType
    SPAM = "spam"
    HAM = "ham"
    UNTRAINED = "untrained"
    # classified as spam, but need to confirm
    MAYBE_SPAM = "maybe_spam"
    MAYBE_HAM = "maybe_ham"
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
  after_create :should_ban_user, if: :trainable?
  after_update :should_ban_user, if: :trainable_type_changed?


  def should_ban_user
    if [ GroupClassifierState::TELEGRAM_DATA_COLLECTOR_GROUP_ID, GroupClassifierState::USER_NAME_CLASSIFIER_GROUP_ID ].include? self.group_id
      Rails.logger.info "Shouldn't ban user in non-existing group"
      return
    end
    # imported trained data set from CSV
    if [ 0 ].include? self.sender_chat_id
      Rails.logger.info "Shouldn't ban non-existing user"
      return
    end

    spam_ban_threshold = Rails.application.config.spam_ban_threshold
    spam_count = TrainedMessage.where(group_id: self.group_id, sender_chat_id: self.sender_chat_id, message_type: :spam).count
    if spam_count >= spam_ban_threshold && is_bot_admin_of_group?(self.group_id)
      Rails.logger.info "user: #{self.sender_user_name} sent more than 3 spam messages in group: #{self.group_id}, ban this user from group"
      TelegramBackgroundWorkerJob.perform_later(
        action: PostAction::BAN_USER,
        trained_message: self
      )
    end
  end

  def is_bot_admin_of_group?(group_id)
    bot_id = Rails.cache.fetch("bot_id", expires_in: 24.hours) do
      bot.api.get_me.id
    end
    cache_key = "#{group_id}_group_chat_member"
    chat_member = Rails.cache.fetch(cache_key, expires_in: 1.hours) do
      bot.api.get_chat_member(chat_id: group_id, user_id: bot_id)
      return [ "administrator", "creator" ].include?(chat_member.status) && chat_member.can_restrict_members
    end
  end

  def bot
    @bot ||= Telegram::Bot::Client.new(Rails.application.credentials.dig(:telegram_bot_token))
  end

  def retrain_classifier
    return if untrained?

    BatchProcessor.add_to_batch(
      "classifier_training_batch_key",
      "ClassifierTrainerJob",
      self,                     # pass trainedMessage as item_data
      {},                        # no shared_args needed
      batch_size: 100,
      batch_window: 5.minutes
    )
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
