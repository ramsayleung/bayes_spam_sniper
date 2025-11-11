require "test_helper"
require "minitest/mock"

class TelegramBotterTest < ActiveSupport::TestCase
  setup do
    @botter = TelegramBotter.new
    @bot = Minitest::Mock.new
    @botter.instance_variable_set(:@bot_username, "my_bot")
    @botter.instance_variable_set(:@bot_id, 123_456)
    # Mock the logger to prevent logging during tests
    Rails.logger = ActiveSupport::Logger.new(nil)
  end

  def test_ignores_command_for_other_bot_in_group
    message = OpenStruct.new(
      text: "/start@another_bot",
      chat: OpenStruct.new(type: "group"),
      from: OpenStruct.new(language_code: "en")
    )

    # We expect `handle_start_command` NOT to be called.
    mock = Minitest::Mock.new
    # No expectations on the mock, so if it's called, it will raise.

    @botter.stub(:handle_start_command, mock) do
      @botter.send(:handle_message, @bot, message)
    end

    assert mock.verify
  end

  def test_processes_command_for_this_bot_in_group
    message = OpenStruct.new(
      text: "/start@my_bot",
      chat: OpenStruct.new(type: "group"),
      from: OpenStruct.new(language_code: "en")
    )

    mock = Minitest::Mock.new
    mock.expect(:call, nil, [ @bot, message ])

    @botter.stub(:handle_start_command, mock) do
      @botter.send(:handle_message, @bot, message)
    end

    assert mock.verify
  end

  def test_processes_command_without_at_in_group
    message = OpenStruct.new(
      text: "/start",
      chat: OpenStruct.new(type: "group"),
      from: OpenStruct.new(language_code: "en")
    )

    mock = Minitest::Mock.new
    mock.expect(:call, nil, [ @bot, message ])

    @botter.stub(:handle_start_command, mock) do
      @botter.send(:handle_message, @bot, message)
    end

    assert mock.verify
  end

  def test_processes_command_for_another_bot_in_private_chat
    # In private chat, any command should be handled, even if it has @another_bot.
    # The logic is that user is talking to THIS bot.
    message = OpenStruct.new(
      text: "/start@another_bot",
      chat: OpenStruct.new(type: "private"),
      from: OpenStruct.new(language_code: "en")
    )

    mock = Minitest::Mock.new
    mock.expect(:call, nil, [ @bot, message ])

    @botter.stub(:handle_start_command, mock) do
      @botter.send(:handle_message, @bot, message)
    end

    assert mock.verify
  end

  def test_handle_regular_message_not_spam
    message = OpenStruct.new(text: "this is a normal message", chat: OpenStruct.new(id: 123, title: "test group"), from: OpenStruct.new)
    spam_detection_result = OpenStruct.new(is_spam: false)

    spam_service_instance_mock = Minitest::Mock.new
    spam_service_instance_mock.expect(:process, spam_detection_result)

    SpamDetectionService.stub(:new, ->(msg) {
      assert_equal message, msg
      spam_service_instance_mock
    }) do
      @botter.stub(:is_in_whitelist?, false) do
        @botter.send(:handle_regular_message, @bot, message)
      end
    end

    assert spam_service_instance_mock.verify
  end

  def test_handle_regular_message_is_spam
    message = OpenStruct.new(
      text: "this is spam",
      chat: OpenStruct.new(id: 123, title: "test group"),
      from: OpenStruct.new(id: 999, first_name: "spammer", last_name: nil),
      message_id: 789
    )
    spam_detection_result = OpenStruct.new(is_spam: true)

    spam_service_instance_mock = Minitest::Mock.new
    spam_service_instance_mock.expect(:process, spam_detection_result)

    api_mock = Minitest::Mock.new
    api_mock.expect(:delete_message, nil, chat_id: 123, message_id: 789)
    api_mock.expect(:send_message, OpenStruct.new(chat: OpenStruct.new(id: 123), message_id: 101112)) do |args|
      args[:chat_id] == 123 && args[:text].include?("spammer")
    end

    @bot.expect(:api, api_mock)
    @bot.expect(:api, api_mock)

    TelegramBackgroundWorkerJob.stub(:set, ->(wait:) {
      job_mock = Minitest::Mock.new
      job_mock.expect(:perform_later, nil)
      job_mock
    }) do
      SpamDetectionService.stub(:new, ->(msg) {
        assert_equal message, msg
        spam_service_instance_mock
      }) do
        @botter.stub(:is_in_whitelist?, false) do
          @botter.send(:handle_regular_message, @bot, message)
        end
      end
    end

    assert spam_service_instance_mock.verify
    assert api_mock.verify
  end

  def test_handle_regular_message_from_whitelisted_user
    message = OpenStruct.new(text: "this is a message from admin", chat: OpenStruct.new(id: 123, title: "test group"), from: OpenStruct.new)

    # We expect SpamDetectionService.new to NOT be called.
    # fails the test if it's ever invoked.
    SpamDetectionService.stub(:new, ->(*args) { flunk "SpamDetectionService.new should not be called for a whitelisted user" }) do
      @botter.stub(:is_in_whitelist?, true) do
        @botter.send(:handle_regular_message, @bot, message)
      end
    end

    # If the test reaches this point without `flunk` being called, it means the stub was not invoked,
    # which is the desired outcome.
    assert true, "Test passed because SpamDetectionService.new was not called."
  end

  def test_handle_regular_message_reply_to_bot
    message = OpenStruct.new(
      text: "this is a reply to the bot",
      chat: OpenStruct.new(id: 123, title: "test group"),
      from: OpenStruct.new,
      reply_to_message: OpenStruct.new(from: OpenStruct.new(id: @botter.instance_variable_get(:@bot_id)))
    )

    # We expect SpamDetectionService.new to NOT be called, as replies to the bot are whitelisted.
    SpamDetectionService.stub(:new, ->(*args) { flunk "SpamDetectionService.new should not be called for a reply to the bot" }) do
      # is_in_whitelist? should handle this, so we don't need to stub it directly for this test's purpose.
      @botter.send(:handle_regular_message, @bot, message)
    end

    assert true, "Test passed because SpamDetectionService.new was not called."
  end
end
