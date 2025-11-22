class ClassifierTrainerJob < ApplicationJob
  # Job to train classifier asynchronously
  queue_as :training

  def perform(trained_messages)
    start_time = Time.current
    Rails.logger.info "Retraining classifiers."

    trained_message_ids = trained_messages.map { |data| data["id"] }
    trained_messages = TrainedMessage.where(id: trained_message_ids)

    # Separate messages by their training target
    user_name_messages     = trained_messages.select(&:user_name?)
    message_content_messages = trained_messages.select(&:message_content?)

    if user_name_messages.any?
      username_start_time = Time.current

      GroupClassifierState.username.find_each do |classifier|
        spam_classifier = SpamClassifierService.new(classifier.group_id, classifier.group_name)
        spam_classifier.train_batch(user_name_messages)
      end

      username_duration = Time.current - username_start_time
      Rails.logger.info "Username classifier training completed in #{username_duration.round(2)} seconds with #{user_name_messages.count} messages."
    end

    if message_content_messages.any?
      group_start_time = Time.current

      GroupClassifierState.for_group.find_each do |classifier|
        spam_classifier = SpamClassifierService.new(classifier.group_id, classifier.group_name)
        spam_classifier.train_batch(message_content_messages)
      end

      group_duration = Time.current - group_start_time
      Rails.logger.info "Group classifier training completed in #{group_duration.round(2)} seconds with #{message_content_messages.count} messages."
    end

    total_duration = Time.current - start_time
    Rails.logger.info "Classifier training job completed in #{total_duration.round(2)} seconds."
  end
end
