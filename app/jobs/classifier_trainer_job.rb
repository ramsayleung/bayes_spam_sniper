class ClassifierTrainerJob < ApplicationJob
  # Job to train classifier asynchronously
  queue_as :training

  def perform(group_id, group_name)
    SpamClassifierService.rebuild_for_group(group_id, group_name)
  end
end
