require "test_helper"
require "minitest/mock"

class RuleBasedClassifierIntegrationTest < ActiveSupport::TestCase
  test "returns spam if message is spam with excessive spacing" do
    spam_text = "跟 单 像 捡 钱 ！ 再 不 进 群 是 傻 狗 ！"
    service = RuleBasedClassifier.new(spam_text)
    result = service.send(:check_chinese_spacing_spam)
    assert result.is_spam
    assert_equal TrainedMessage::TrainingTarget::MESSAGE_CONTENT, result.target
  end

  test "return non-spam if message has normal spacing" do
    text = " Q妹，我私信你 U理财 "
    service = RuleBasedClassifier.new(text)
    result = service.send(:check_chinese_spacing_spam)
    assert_not result.is_spam

    text = "Combot警告了Donald Williams (1/1)"
    service = RuleBasedClassifier.new(text)
    result = service.send(:check_chinese_spacing_spam)
    assert_not result.is_spam
  end
end
