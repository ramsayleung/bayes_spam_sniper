class ClassifierTrainerJob < ApplicationJob
  # Job to train classifier asynchronously
  queue_as :training

  def perform(trained_messages)
    Rails.logger.info "Retraining classifiers."
    trained_message_ids = trained_messages.map { |data| data["id"] }
    trained_messages = TrainedMessage.where(id: trained_message_ids)

    # Separate messages by their training target
    user_name_messages     = trained_messages.select(&:user_name?)
    message_content_messages = trained_messages.select(&:message_content?)

    if user_name_messages.any?
      GroupClassifierState.username.find_each do |classifier|
        spam_classifier = SpamClassifierService.new(classifier.group_id, classifier.group_name)
        spam_classifier.train_batch(user_name_messages)
      end
    end

    if message_content_messages.any?
      GroupClassifierState.for_group.find_each do |classifier|
        spam_classifier = SpamClassifierService.new(classifier.group_id, classifier.group_name)
        spam_classifier.train_batch(message_content_messages)
      end
    end
  end
end
