# test/services/spam_classifier_service_test.rb
require "test_helper"

class SpamClassifierServiceTest < ActiveSupport::TestCase
  def setup
    @group_id = 12345
    @group_name = "test group"
  end

  test "should initialize a new classifier state for a new group" do
    service = SpamClassifierService.new(@group_id, @group_name)
    assert_difference "GroupClassifierState.count", 1 do
      SpamClassifierService.new(99999, "new group")
    end

    assert_equal @group_id, service.group_id
    assert_not_nil service.classifier_state
    assert_equal 0, service.classifier_state.total_spam_messages
  end

  test "should not create a new classifier state if one already exists" do
    _service = SpamClassifierService.new(@group_id, @group_name)
    assert_no_difference "GroupClassifierState.count" do
      SpamClassifierService.new(@group_id, @group_name)
    end
  end

  test "it creates a new classifier from the most recent template if one exists" do
    _old_template = GroupClassifierState.create!(
      group_id: -100, group_name: "Old Public Group", total_spam_words: 10,
    )
    recent_template = GroupClassifierState.create!(
      group_id: -200, group_name: "Recent Public Group",
      total_spam_words: 99, spam_counts: { "viagra" => 10 },
    )

    service = nil
    assert_difference "GroupClassifierState.count", 1 do
      service = SpamClassifierService.new(456, "New Derived Group")
    end

    puts "recent_template: #{recent_template.inspect}"
    new_classifier = service.classifier_state
    assert_equal 456, new_classifier.group_id
    assert_equal "New Derived Group", new_classifier.group_name
    assert_equal recent_template.total_spam_words, new_classifier.total_spam_words
    assert_equal recent_template.spam_counts, new_classifier.spam_counts

    # Assert that the hash is a copy, not the same object.
    refute_same recent_template.spam_counts, new_classifier.spam_counts
  end

  test "#train should correctly update state for a new spam message" do
    spam_message = "快来买便宜的伟哥"
    trained_message = TrainedMessage.new(
      group_id: @group_id,
      message: spam_message,
      message_type: :spam,
      sender_chat_id: 111,
      sender_user_name: "Spammer"
    )

    service = SpamClassifierService.new(@group_id, @group_name)
    service.train(trained_message)
    state = service.classifier_state.reload

    assert_equal 1, state.total_spam_messages
    assert_equal 0, state.total_ham_messages
    assert_equal 5, state.total_spam_words

    assert state.spam_counts["便宜"] >= 1
    assert_nil state.ham_counts["便宜"]
  end

  test "#train should correctly update state for a new ham message" do
    ham_message = "我们明天开会讨论项目"
    trained_message = TrainedMessage.new(
      group_id: @group_id,
      message: ham_message,
      message_type: :ham,
      sender_chat_id: 222,
      sender_user_name: "Teammate"
    )

    service = SpamClassifierService.new(@group_id, @group_name)
    service.train(trained_message)

    state = service.classifier_state.reload

    assert_equal 0, state.total_spam_messages
    assert_equal 1, state.total_ham_messages
    assert state.ham_counts["项目"] >= 1
    assert_nil state.spam_counts["项目"]
  end

  test "#toenize should handle emoji correctly" do
    service = SpamClassifierService.new(@group_id, @group_name)
    spam_message =" 🚘🚘🚘还在死扛单 🚘🚘🚘 这里策略准到爆 进群免费体验 @hakaoer 🚘🚘🚘不满意随便喷🚘🚘🚘 "
    tokens = service.tokenize(spam_message)

    assert_includes tokens, "🚘"
    assert_includes tokens, "扛单" # user-defined dictionary
    assert_equal 12, tokens.filter { |t| t =="🚘" }.length()
  end

  test "#toenize should handle punctuation correctly" do
    service = SpamClassifierService.new(@group_id, @group_name)
    spam_message = "这人简-介挂的 合-约-报单群组挺牛的ETH500点，大饼5200点！ + @BTCETHl6666"
    tokens = service.tokenize(spam_message)
    assert_includes tokens, "简介"
    assert_includes tokens, "合约"
    assert_includes tokens, "报单"
    assert_includes tokens, "群组"
    assert_includes tokens, "大饼"
  end

  test "#tokenize should handle user-defined dictionary correct" do
    service = SpamClassifierService.new(@group_id, @group_name)
    spam_message ="在 币圈 想 赚 钱，那 你 不关 注 这 个 王 牌 社 区，真的太可惜了，真 心 推 荐，每 天 都 有 免 费 策 略"
    tokens = service.tokenize(spam_message)
    # 币圈 is user-defined word
    assert_includes tokens, "币圈"
  end

  test "#classify should return false if the model is not trained" do
    service = SpamClassifierService.new(@group_id, @group_name)
    is_spam, _ = service.classify("some random message")
    assert_not is_spam
  end

  test "#classify should correctly identify a message as spam" do
    service = SpamClassifierService.new(@group_id, @group_name)
    service.train(TrainedMessage.new(
                    group_id: @group_id,
                    message: "便宜的伟哥现在买",
                    message_type: :spam,
                    sender_chat_id: 1,
                    sender_user_name: "s"
                  ))
    service.train(TrainedMessage.new(
                    group_id: @group_id,
                    message: "免费点击这里",
                    message_type: :spam,
                    sender_chat_id: 1,
                    sender_user_name: "s"
                  ))
    service.train(TrainedMessage.new(
                    group_id: @group_id,
                    message: "你好，今天天气不错",
                    message_type: :ham,
                    sender_chat_id: 2,
                    sender_user_name: "s"
                  ))

    is_spam, p_spam = service.classify("点击这里买伟哥")

    assert is_spam, "Message should be classified as spam"
    assert p_spam > 0.5, "Spam score should be higher than ham score"
  end

  test "#train_batch train a list of messages and identify spam message correctly" do
    service = SpamClassifierService.new(@group_id, @group_name)
    service.train_batch([
                          TrainedMessage.new(
                            group_id: @group_id,
                            message: "便宜的伟哥现在买",
                            message_type: :spam,
                            sender_chat_id: 1,
                            sender_user_name: "s"
                          ),
                          TrainedMessage.new(
                            group_id: @group_id,
                            message: "免费点击这里",
                            message_type: :spam,
                            sender_chat_id: 1,
                            sender_user_name: "s"
                          ),
                          TrainedMessage.new(
                            group_id: @group_id,
                            message: "你好，今天天气不错",
                            message_type: :ham,
                            sender_chat_id: 2,
                            sender_user_name: "s"
                          )
                        ])
    is_spam, p_spam = service.classify("点击这里买伟哥")

    assert is_spam, "Message should be classified as spam"
    assert p_spam > 0.5, "Spam score should be higher than ham score"
  end

  test "#classify should correctly identify a message as ham" do
    service = SpamClassifierService.new(@group_id, @group_name)
    service.train(TrainedMessage.new(
                    group_id: @group_id,
                    message: "便宜的伟哥现在买",
                    message_type: :spam,
                    sender_chat_id: 1,
                    sender_user_name: "s"
                  ))
    service.train(TrainedMessage.new(
                    group_id: @group_id,
                    message: "你好，今天天气不错",
                    message_type: :ham,
                    sender_chat_id: 1,
                    sender_user_name: "s"
                  ))
    service.train(TrainedMessage.new(
                    group_id: @group_id,
                    message: "我们明天开会",
                    message_type: :ham,
                    sender_chat_id: 2,
                    sender_user_name: "s"
                  ))

    is_spam, p_spam = service.classify("我们明天见")

    state = service.classifier_state

    assert_not is_spam, "Message should be classified as ham"
    assert p_spam < 0.5, "Ham score should be higher than spam score"
  end
end
