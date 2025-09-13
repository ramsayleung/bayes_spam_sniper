module TrainedMessagesHelper
  def message_type_classes(message_type)
    case message_type
    when "spam"
      "bg-red-100 text-red-800"
    when "ham"
      "bg-green-100 text-green-800"
    when "maybe_spam"
      "bg-orange-100 text-orange-800"
    when "maybe_ham"
      "bg-lime-100 text-lime-800"
    when "untrained"
      "bg-gray-100 text-gray-800"
    else
      "bg-gray-100 text-gray-800"
    end
  end

  def training_target_classes(training_target)
    case training_target
    when "message_content"
      "bg-blue-100 text-blue-800"
    when "user_name"
      "bg-purple-100 text-purple-800"
    else
      "bg-yellow-100 text-yellow-800"
    end
  end
end
