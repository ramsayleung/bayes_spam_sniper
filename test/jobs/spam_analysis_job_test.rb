require "test_helper"
require "minitest/mock"

class SpamAnalysisJobTest < ActiveSupport::TestCase
  setup do
    @job = SpamAnalysisJob.new
    # Mock the logger to prevent logging during tests
    Rails.logger = ActiveSupport::Logger.new(nil)
  end

  def test_perform_with_non_spam_message
    message_data = {
      message_id: 789,
      text: "this is a normal message",
      chat_id: 123,
      chat_type: "supergroup",
      chat_title: "test group",
      from_id: 999,
      from_first_name: "normal",
      from_last_name: "user",
      date: Time.current,
      quote_text: nil,
      reply_to_text: nil
    }

    # Mock the spam detection to return non-spam
    spam_detection_result = OpenStruct.new(is_spam: false)
    spam_service_instance_mock = Minitest::Mock.new
    spam_service_instance_mock.expect(:process, spam_detection_result)

    SpamDetectionService.stub(:new, ->(msg) {
      # Verify that message text matches
      assert_equal "this is a normal message", msg.text
      spam_service_instance_mock
    }) do
      @job.perform(message_data)
    end

    assert spam_service_instance_mock.verify
  end

  def test_perform_with_spam_message
    message_data = {
      message_id: 789,
      text: "this is spam message",
      chat_id: 123,
      chat_type: "supergroup",
      chat_title: "test group",
      from_id: 999,
      from_first_name: "spammer",
      from_last_name: "user",
      date: Time.current,
      quote_text: nil,
      reply_to_text: nil
    }

    # Mock the spam detection to return spam
    spam_detection_result = OpenStruct.new(is_spam: true)
    spam_service_instance_mock = Minitest::Mock.new
    spam_service_instance_mock.expect(:process, spam_detection_result)

    # Mock the bot API with simple stubbing
    api_mock = Minitest::Mock.new
    api_mock.expect(:delete_message, true, chat_id: 123, message_id: 789)
    api_mock.expect(:send_message, OpenStruct.new(chat: OpenStruct.new(id: 123), message_id: 101112),
                    chat_id: 123, text: String, parse_mode: "Markdown")

    bot_instance = Minitest::Mock.new
    bot_instance.expect(:api, api_mock)  # First call
    bot_instance.expect(:api, api_mock)  # Second call

    # Mock the credentials and bot client
    Rails.application.stub(:credentials, OpenStruct.new(telegram_bot_token: "test_token")) do
      Telegram::Bot::Client.stub(:new, bot_instance) do
        TelegramMemberFetcher.stub(:get_bot_chat_member, OpenStruct.new(can_delete_messages: true)) do
          TelegramBackgroundWorkerJob.stub(:set, ->(wait:) {
            set_mock = Minitest::Mock.new
            set_mock.expect(:perform_later, true, action: PostAction::DELETE_ALERT_MESSAGE, chat_id: 123, message_id: 101112)
            set_mock
          }) do
            SpamDetectionService.stub(:new, ->(msg) {
              assert_equal "this is spam message", msg.text
              spam_service_instance_mock
            }) do
              @job.perform(message_data)
            end
          end
        end
      end
    end

    assert spam_service_instance_mock.verify
    assert api_mock.verify
    assert bot_instance.verify
  end

  def test_perform_with_nil_message_text
    message_data = {
      message_id: 789,
      text: nil,
      chat_id: 123,
      chat_type: "supergroup",
      chat_title: "test group",
      from_id: 999,
      from_first_name: "normal",
      from_last_name: "user",
      date: Time.current,
      quote_text: nil,
      reply_to_text: nil
    }

    # Should not call SpamDetectionService for nil text
    SpamDetectionService.stub(:new, ->(*) {
      flunk "SpamDetectionService.new should not be called for nil message text"
    }) do
      @job.perform(message_data)
    end

    assert true
  end
end
