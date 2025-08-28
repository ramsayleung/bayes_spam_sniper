# test/services/spam_classifier_service_test.rb
require 'test_helper'

class SpamClassifierServiceTest < ActiveSupport::TestCase
  def setup
    @group_id = 12345
    @group_name = "test group"
    @service = SpamClassifierService.new(@group_id, @group_name)
  end

  test "should initialize a new classifier state for a new group" do
    assert_difference "GroupClassifierState.count", 1 do
      SpamClassifierService.new(99999, @group_name)
    end

    assert_equal @group_id, @service.group_id
    assert_not_nil @service.classifier_state
    assert_equal 0, @service.classifier_state.total_spam_messages
  end

  test "should not create a new classifier state if one already exists" do
    assert_no_difference "GroupClassifierState.count" do
      SpamClassifierService.new(@group_id, @group_name)
    end
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
    @service.train(trained_message)
    state = @service.classifier_state.reload

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

    @service.train(trained_message)
    
    state = @service.classifier_state.reload

    assert_equal 0, state.total_spam_messages
    assert_equal 1, state.total_ham_messages
    assert state.ham_counts["项目"] >= 1
    assert_nil state.spam_counts["项目"]
  end

  test "#cleanup should handle any anti-spam separators" do
    spam_variants = [
      "合-约*报@单群组",
      "B#T@C$500点",
      "稳.赚.不.亏.的",
      "联,系,我,们",
    ]

    expected_variants = [
      "合约报单群组",
      "BTC500 点",
      "稳赚不亏的",
      "联系我们"
    ]
  
    spam_variants.each_with_index do |variant, index|
      expected_text = expected_variants[index]
      cleaned_text = @service.clean_text(variant)
      puts "cleaned_text #{cleaned_text}"
      cleaned_text = @service.clean_text(variant)
      assert_equal expected_text, cleaned_text, "Failed on input: '#{variant}'"
    
      # Should NOT contain separator characters
      refute cleaned_text.match?(/[*@#$,.-]/)
    end
  end

  test "#toenize should handle punctuation correctly" do
    spam_message = "这人简-介挂的 合-约-报单群组挺牛的ETH500点，大饼5200点！ + @BTCETHl6666"
    cleaned_text = @service.clean_text(spam_message)
    assert_equal "这人简介挂的合约报单群组挺牛的 ETH500 点大饼 5200 点！ + @BTCETHl6666", cleaned_text
    tokens = @service.tokenize(spam_message)
    assert_includes tokens, "简介"
    assert_includes tokens, "合约"
    assert_includes tokens, "报单"
    assert_includes tokens, "群组"
    assert_includes tokens, "大饼"
  end

  test "#classify should return false if the model is not trained" do
    is_spam, _, _ = @service.classify("some random message")
    assert_not is_spam
  end

  test "#classify should correctly identify a message as spam" do
    @service.train(TrainedMessage.new(
                     group_id: @group_id,
                     message: "便宜的伟哥现在买",
                     message_type: :spam,
                     sender_chat_id: 1,
                     sender_user_name: "s"
                   ))
    @service.train(TrainedMessage.new(
                     group_id: @group_id,
                     message: "免费点击这里",
                     message_type: :spam,
                     sender_chat_id: 1,
                     sender_user_name: "s"
                   ))
    @service.train(TrainedMessage.new(
                     group_id: @group_id,
                     message: "你好，今天天气不错",
                     message_type: :ham,
                     sender_chat_id: 2,
                     sender_user_name: "s"
                   ))

    is_spam, spam_score, ham_score = @service.classify("点击这里买伟哥")

    assert is_spam, "Message should be classified as spam"
    assert spam_score > ham_score, "Spam score should be higher than ham score"
  end

  test "#classify should correctly identify a message as ham" do
    @service.train(TrainedMessage.new(
                     group_id: @group_id,
                     message: "便宜的伟哥现在买",
                     message_type: :spam,
                     sender_chat_id: 1,
                     sender_user_name: "s"
                   ))
    @service.train(TrainedMessage.new(
                     group_id: @group_id,
                     message: "你好，今天天气不错",
                     message_type: :ham,
                     sender_chat_id: 1,
                     sender_user_name: "s"
                   ))
    @service.train(TrainedMessage.new(
                     group_id: @group_id,
                     message: "我们明天开会",
                     message_type: :ham,
                     sender_chat_id: 2,
                     sender_user_name: "s"
                   ))

    is_spam, spam_score, ham_score = @service.classify("我们明天见")

    state = @service.classifier_state

    assert_not is_spam, "Message should be classified as ham"
    puts "ham_score: #{ham_score}, spam_score: #{spam_score} spam_counts: #{state.spam_counts}, ham_counts: #{state.ham_counts}"
    assert ham_score > spam_score, "Ham score should be higher than spam score"
  end
end
