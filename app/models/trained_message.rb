class TrainedMessage < ApplicationRecord
  enum :message_type, { spam: 0, ham: 1 , untrained: 2}

  scope :shared, -> { where(group_id: 0) }

  validates :group_id, presence: true
  validates :message, presence: true
  validates :message_type, presence: true
  
  # Automatically train classifier after creating/updating a message
  after_create :retrain_classifier, if: :trainable?
  after_update :retrain_classifier, if: :trainable_type_changed?
  after_destroy :retrain_classifier, if: :trainable?

  def retrain_classifier
    return if untrained?
    # For efficiency, we could queue this as a background job
    ClassifierTrainerJob.perform_later(group_id, group_name)
  end

  private

  def trainable?
    spam? || ham?
  end

  def trainable_type_changed?
    return false unless saved_change_to_message_type?

    old_type, new_type = saved_change_to_message_type
    (old_type != 'untrained') || (new_type != 'untrained')
  end
end
