class TrainedMessage < ApplicationRecord
  enum :message_type, { spam: 0, ham: 1 }

  scope :shared, -> { where(group_id: 0) }

  validates :group_id, presence: true
  validates :message, presence: true
  validates :message_type, presence: true
  
  # Automatically train classifier after creating/updating a message
  after_create :retrain_classifier
  after_update :retrain_classifier, if: :saved_change_to_message_type?
  after_destroy :retrain_classifier

  def retrain_classifier
    # For efficiency, we could queue this as a background job
    ClassifierTrainerJob.perform_later(group_id, group_name)
  end
end
