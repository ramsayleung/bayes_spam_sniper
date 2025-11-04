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
end
