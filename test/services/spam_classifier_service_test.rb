# test/services/spam_classifier_service_test.rb
require 'test_helper'

class SpamClassifierServiceTest < ActiveSupport::TestCase
  def setup
    @group_id = 12345
    @service = SpamClassifierService.new(@group_id)
  end

  test "should initialize a new classifier state for a new group" do
    assert_difference "GroupClassifierState.count", 1 do
      SpamClassifierService.new(99999)
    end

    assert_equal @group_id, @service.group_id
    assert_not_nil @service.classifier_state
    assert_equal 0, @service.classifier_state.total_spam_messages
  end

  test "should not create a new classifier state if one already exists" do
    assert_no_difference "GroupClassifierState.count" do
      SpamClassifierService.new(@group_id)
    end
  end

  test "#train should correctly update state for a new spam message" do
    spam_message = "快来买便宜的伟哥"
    sender_id = 111
    sender_name = "Spammer"

    assert_difference "TrainedMessage.count", 1 do
      @service.train(spam_message, sender_id, sender_name, :spam)
    end

    state = @service.classifier_state.reload

    assert_equal 1, state.total_spam_messages
    assert_equal 0, state.total_ham_messages
    assert_equal 5, state.total_spam_words
    
    assert state.spam_counts["便宜"] >= 1
    assert_nil state.ham_counts["便宜"]
  end

  test "#train should correctly update state for a new ham message" do
    ham_message = "我们明天开会讨论项目" # "Let's have a meeting tomorrow to discuss the project"
    sender_id = 222
    sender_name = "Teammate"

    @service.train(ham_message, sender_id, sender_name, :ham)
    
    state = @service.classifier_state.reload

    assert_equal 0, state.total_spam_messages
    assert_equal 1, state.total_ham_messages
    assert state.ham_counts["项目"] >= 1
    assert_nil state.spam_counts["项目"]
  end

  test "#classify should return false if the model is not trained" do
    is_spam, _, _ = @service.classify("some random message")
    assert_not is_spam
  end

  test "#classify should correctly identify a message as spam" do
    @service.train("便宜的伟哥现在买", 1, "s", :spam)
    @service.train("免费点击这里", 1, "s", :spam)
    @service.train("你好，今天天气不错", 2, "h", :ham)

    is_spam, spam_score, ham_score = @service.classify("点击这里买伟哥")

    assert is_spam, "Message should be classified as spam"
    assert spam_score > ham_score, "Spam score should be higher than ham score"
  end

  test "#classify should correctly identify a message as ham" do
    @service.train("便宜的伟哥现在买", 1, "s", :spam)
    @service.train("你好，今天天气不错", 2, "h", :ham)
    @service.train("我们明天开会", 2, "h", :ham)

    is_spam, spam_score, ham_score = @service.classify("我们明天见")

    assert_not is_spam, "Message should be classified as ham"
    assert ham_score > spam_score, "Ham score should be higher than spam score"
  end
end
