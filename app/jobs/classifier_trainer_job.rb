class ClassifierTrainerJob < ApplicationJob
  # Job to train classifier asynchronously
  queue_as :default

  def perform(group_id)
    SpamClassifierService.rebuild_for_group(group_id)
  end
end
