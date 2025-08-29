class BannedUser < ApplicationRecord
  after_destroy :mark_message_as_ham

  private
  def mark_message_as_ham
    TrainedMessage.where(group_id: group_id, sender_chat_id: sender_chat_id, message_id: message_id).update!(message_type: :ham)
  end
end
