class ClassifierTrainerJob < ApplicationJob
  # Job to train classifier asynchronously
  queue_as :training

  def perform(group_id, group_name)
    Rails.logger.info "Retrain all the classifiers for public"
    GroupClassifierState.for_public.find_each do |classifier|
      SpamClassifierService.rebuild_for_group(classifier.group_id, classifier.group_name)
    end
  end
end
