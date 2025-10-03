class MessageTypeSyncJob < ApplicationJob
  queue_as :low_priority

  def perform(message_hash, new_message_type_symbol)
    new_message_type = new_message_type_symbol.to_s

    # 1. Update all messages with the same hash
    new_type_value = TrainedMessage.message_types[new_message_type]

    # Select only messages whose type will *actually* change to prevent unnecessary updates
    messages_to_sync = TrainedMessage.where(message_hash: message_hash)
                         .where.not(message_type: new_message_type)

    messages_to_sync.update_all(message_type: new_type_value, updated_at: Time.current)

    # 2. Trigger Retraining and Ban Checks for all updated messages
    messages_to_sync.each do |message|
      if message.spam? || message.ham?
        BatchProcessor.add_to_batch(
          "classifier_training_batch_key",
          "ClassifierTrainerJob",
          message,
          {},
          batch_size: 100,
          batch_window: 5.minutes
        )
      end
    end
  end
end
