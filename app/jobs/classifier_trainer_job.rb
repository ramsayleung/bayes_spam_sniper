class ClassifierTrainerJob < ApplicationJob
  # Job to train classifier asynchronously
  queue_as :training

  def perform(trained_message)
    Rails.logger.info "Retrain all the classifiers for public"
    if trained_message.user_name?
      GroupClassifierState.username.find_each do |classifier|
        spam_classifier = SpamClassifierService.new(classifier.group_id, classifier.group_name)
        spam_classifier.train(trained_message)
      end
    elsif trained_message.message_content?
      GroupClassifierState.for_group.find_each do |classifier|
        spam_classifier = SpamClassifierService.new(classifier.group_id, classifier.group_name)
        spam_classifier.train(trained_message)
      end
    end
  end
end
