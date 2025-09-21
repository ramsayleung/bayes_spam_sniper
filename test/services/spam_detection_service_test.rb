require "test_helper"
require "ostruct"

class SpamDetectionServiceIntegrationTest < ActiveSupport::TestCase
  fixtures :group_classifier_states, :trained_messages

  def setup
    @main_group_state = group_classifier_states(:main_group_state)

    @chat = OpenStruct.new(id: @main_group_state.group_id, title: @main_group_state.group_name)
    @from = OpenStruct.new(id: 987654321, first_name: "John", last_name: "Doe")
    @username = "John Doe"

    main_classifier = SpamClassifierService.new(@main_group_state.group_id, @main_group_state.group_name)

    spam_messages = [ "合-约*报@单群组", "这人简-介挂的 合-约-报单群组挺牛的ETH500点，大饼5200点！ + @BTCETHl6666" ]
    ham_messages = [ "今天一起吃饭", "今晚开车回家" ]

    spam_messages.each do |msg|
      trained_msg = TrainedMessage.new(message: msg, message_type: :spam)
      main_classifier.train(trained_msg)
    end
    ham_messages.each do |msg|
      trained_msg = TrainedMessage.new(message: msg, message_type: :ham)
      main_classifier.train(trained_msg)
    end

    username_state = group_classifier_states(:username_classifier_state)
    username_classifier = SpamClassifierService.new(username_state.group_id, username_state.group_name)

    spam_usernames = [ "Crypto King", "spam_last_name Bot" ] # Add the word we're testing for
    ham_usernames = [ "David Chen", "Alice Johnson" ]

    spam_usernames.each do |name|
      # Note: training_target doesn't matter for the training logic itself
      username_classifier.train(TrainedMessage.new(message: name, message_type: :spam))
    end
    ham_usernames.each do |name|
      username_classifier.train(TrainedMessage.new(message: name, message_type: :ham))
    end
  end

  test "returns non-spam result for an invalid (empty) message" do
    tg_message = OpenStruct.new(chat: @chat, from: @from, text: " ", message_id: 123)
    service = SpamDetectionService.new(tg_message)

    assert_no_difference "TrainedMessage.count" do
      @result = service.process
    end

    assert_not @result.is_spam
  end

  test "returns spam result if a pre-existing message is marked as spam" do
    pre_existing_message = trained_messages(:pre_existing_spam)

    tg_message = OpenStruct.new(chat: @chat, from: @from, text: pre_existing_message.message, message_id: 123)
    service = SpamDetectionService.new(tg_message)

    result = nil
    TelegramMemberFetcher.stub(:get_bot_chat_member, OpenStruct.new(status: "administrator", can_restrict_members: true)) do
      result = service.process
    end

    assert result.is_spam
    assert_equal TrainedMessage::TrainingTarget::MESSAGE_CONTENT, result.target
  end

  test "returns spam result even if a pre-existing message is marked as ham" do
    pre_existing_message = trained_messages(:pre_existing_ham)
    from = OpenStruct.new(id: 987654321, first_name: "Jon", last_name: "spam_last_name")

    tg_message = OpenStruct.new(chat: @chat, from: from, text: pre_existing_message.message, message_id: 123)
    service = SpamDetectionService.new(tg_message)

    result = service.process

    assert result.is_spam
    assert_equal TrainedMessage::TrainingTarget::USER_NAME, result.target
  end

  test "classifies message as spam when content contains strong spam signals" do
    message_text = "看合约扛单"
    tg_message = OpenStruct.new(chat: @chat, from: @from, text: message_text, message_id: 123)
    service = SpamDetectionService.new(tg_message)

    assert_difference "TrainedMessage.count", 1 do
      @result = service.process
    end

    assert @result.is_spam
    assert_equal TrainedMessage::TrainingTarget::MESSAGE_CONTENT, @result.target
  end
end
