class AddBootstrapHamTrainedMessages < ActiveRecord::Migration[8.0]
  HAM_EXAMPLES = [
    "你好大家", "早安", "谢谢分享", "大家好", "祝好",
    "感谢", "辛苦了", "加油", "不错", "很好",
    "Hello everyone", "Good morning", "Thanks", "Have a great day"
  ].freeze

  def up
    puts "Adding initial ham trained messages..."
    HAM_EXAMPLES.each do |message_text|
      TrainedMessage.create!(
        group_id: 0,
        message: message_text,
        message_type: :ham,
        sender_chat_id: 0,
        sender_user_name: "System"
      )
    end


  end
  
  def down
    puts "Removing initial ham trained messages..."
    TrainedMessage.where(
      sender_user_name: "System",
      group_id: 0,
      sender_chat_id: 0,
      message_type: :ham,
      message: HAM_EXAMPLES # This ensures only the exact messages are matched
    ).destroy_all
  end
end
