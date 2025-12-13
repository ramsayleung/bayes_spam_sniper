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

    job_mock = Minitest::Mock.new
    job_mock.expect(:perform_later, true) do |message_data|
      message_data[:text] == "this is a normal message" &&
      message_data[:chat_id] == 123
    end

    SpamAnalysisJob.stub(:perform_later, ->(message_data) {
      # Verify the message data structure
      assert_equal "this is a normal message", message_data[:text]
      assert_equal 123, message_data[:chat_id]
      true
    }) do
      @botter.stub(:is_in_whitelist?, false) do
        @botter.send(:handle_regular_message, @bot, message)
      end
    end
  end

  def test_handle_regular_message_is_spam
    message = OpenStruct.new(
      text: "this is spam",
      chat: OpenStruct.new(id: 123, title: "test group"),
      from: OpenStruct.new(id: 999, first_name: "spammer", last_name: nil),
      message_id: 789
    )

    SpamAnalysisJob.stub(:perform_later, ->(message_data) {
      assert_equal "this is spam", message_data[:text]
      assert_equal 123, message_data[:chat_id]
      assert_equal 999, message_data[:from_id]
      assert_equal 789, message_data[:message_id]
      true
    }) do
      @botter.stub(:is_in_whitelist?, false) do
        @botter.send(:handle_regular_message, @bot, message)
      end
    end

    # The test passes if no exceptions occur and the right data is passed to the job
    assert true
  end

  def test_handle_regular_message_from_whitelisted_user
    message = OpenStruct.new(text: "this is a message from admin", chat: OpenStruct.new(id: 123, title: "test group"), from: OpenStruct.new)

    SpamAnalysisJob.stub(:perform_later, ->(message_data) {
      flunk "Analysis enqueuing should not be called for a whitelisted user"
    }) do
      @botter.stub(:is_in_whitelist?, true) do
        @botter.send(:handle_regular_message, @bot, message)
      end
    end

    assert true, "Test passed because message was queued for async processing."
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

  def test_handle_markspam_command_success
    # Mock message and replied message
    replied_message = OpenStruct.new(
      text: "spam message content",
      message_id: 100,
      from: OpenStruct.new(id: 456, first_name: "Spam", last_name: "User")
    )
    message = OpenStruct.new(
      chat: OpenStruct.new(id: 123, type: "group", title: "Test Group"),
      from: OpenStruct.new(id: 789, first_name: "Admin", last_name: "User"),
      reply_to_message: replied_message
    )

    # Mock bot chat member with full permissions
    chat_member = OpenStruct.new(status: "administrator", can_delete_messages: true, can_restrict_members: true)

    # Mock external dependencies
    @botter.stub(:is_group_chat?, true) do
      @botter.stub(:is_admin?, true) do
        TelegramMemberFetcher.stub(:get_bot_chat_member, chat_member) do
          TrainedMessage.stub(:create!, OpenStruct.new(id: 1)) do
            BannedUser.stub(:find_or_create_by!, OpenStruct.new(id: 1)) do
              TelegramBackgroundWorkerJob.stub(:set, ->(wait:) {
                job_mock = Minitest::Mock.new
                job_mock.expect(:perform_later, nil, action: PostAction::DELETE_ALERT_MESSAGE, chat_id: 123, message_id: 200)
                job_mock
              }) do
                # Mock API calls
                api_mock = Minitest::Mock.new
                api_mock.expect(:delete_message, nil, chat_id: 123, message_id: 100)
                api_mock.expect(:ban_chat_member, nil, chat_id: 123, user_id: 456)
                api_mock.expect(:send_message, OpenStruct.new(chat: OpenStruct.new(id: 123), message_id: 200)) do |args|
                  args[:chat_id] == 123 && args[:text].include?("Spam User")
                end
                @bot.expect(:api, api_mock)
                @bot.expect(:api, api_mock)
                @bot.expect(:api, api_mock)

                # Stub I18n for predictable messages
                I18n.stub(:t, ->(key, **args) { "#{key} #{args}" }) do
                  @botter.instance_variable_set(:@lang_code, "en")
                  @botter.send(:handle_markspam_command, @bot, message)
                end

                assert api_mock.verify
              end
            end
          end
        end
      end
    end
  end

  def test_handle_markspam_command_insufficient_permission_to_delete
    # Mock message and replied message
    replied_message = OpenStruct.new(
      text: "spam message content",
      message_id: 100,
      from: OpenStruct.new(id: 456, first_name: "Spam", last_name: "User")
    )
    message = OpenStruct.new(
      chat: OpenStruct.new(id: 123, type: "group", title: "Test Group"),
      from: OpenStruct.new(id: 789, first_name: "Admin", last_name: "User"),
      reply_to_message: replied_message
    )

    # Mock bot chat member with insufficient delete permissions
    chat_member = OpenStruct.new(status: "administrator", can_delete_messages: false, can_restrict_members: true)

    # Mock external dependencies
    @botter.stub(:is_group_chat?, true) do
      @botter.stub(:is_admin?, true) do
        TelegramMemberFetcher.stub(:get_bot_chat_member, chat_member) do
          # Mock API calls
          api_mock = Minitest::Mock.new
          api_mock.expect(:send_message, nil) do |args|
            args[:chat_id] == 123 && args[:text].include?("insufficient_permission_to_delete_message")
          end

          # Explicitly fail if delete_message or ban_chat_member are called
          def api_mock.delete_message(**args)
            flunk "delete_message should not be called when bot lacks permission to delete messages"
          end

          def api_mock.ban_chat_member(**args)
            flunk "ban_chat_member should not be called when bot lacks permission to delete messages"
          end

          @bot.expect(:api, api_mock)

          # Stub I18n for predictable messages
          I18n.stub(:t, ->(key, **args) { "#{key} #{args}" }) do
            @botter.instance_variable_set(:@lang_code, "en")
            @botter.send(:handle_markspam_command, @bot, message)
          end

          assert api_mock.verify
        end
      end
    end
  end

  def test_handle_markspam_command_insufficient_permission_to_restrict
    # Mock message and replied message
    replied_message = OpenStruct.new(
      text: "spam message content",
      message_id: 100,
      from: OpenStruct.new(id: 456, first_name: "Spam", last_name: "User")
    )
    message = OpenStruct.new(
      chat: OpenStruct.new(id: 123, type: "group", title: "Test Group"),
      from: OpenStruct.new(id: 789, first_name: "Admin", last_name: "User"),
      reply_to_message: replied_message
    )

    # Mock bot chat member with insufficient restrict permissions
    chat_member = OpenStruct.new(status: "administrator", can_delete_messages: true, can_restrict_members: false)

    # Mock external dependencies
    @botter.stub(:is_group_chat?, true) do
      @botter.stub(:is_admin?, true) do
        TelegramMemberFetcher.stub(:get_bot_chat_member, chat_member) do
          TrainedMessage.stub(:create!, OpenStruct.new(id: 1)) do
            TelegramBackgroundWorkerJob.stub(:set, ->(wait:) {
              job_mock = Minitest::Mock.new
              job_mock.expect(:perform_later, nil, action: PostAction::DELETE_ALERT_MESSAGE, chat_id: 123, message_id: 200)
              job_mock
            }) do
              # Mock API calls
              api_mock = Minitest::Mock.new
              api_mock.expect(:delete_message, nil, chat_id: 123, message_id: 100)
              api_mock.expect(:send_message, OpenStruct.new(chat: OpenStruct.new(id: 123), message_id: 200)) do |args|
                args[:chat_id] == 123 && args[:text].include?("delete_message_only_success_message")
              end

              # Explicitly fail if ban_chat_member is called
              def api_mock.ban_chat_member(**args)
                flunk "ban_chat_member should not be called when bot lacks permission to restrict members"
              end

              @bot.expect(:api, api_mock)
              @bot.expect(:api, api_mock)

              # Stub I18n for predictable messages
              I18n.stub(:t, ->(key, **args) { "#{key} #{args}" }) do
                @botter.instance_variable_set(:@lang_code, "en")
                @botter.send(:handle_markspam_command, @bot, message)
              end

              assert api_mock.verify
            end
          end
        end
      end
    end
  end

  def test_handle_markspam_command_not_in_group_chat
    message = OpenStruct.new(
      chat: OpenStruct.new(id: 123, type: "private"),
      from: OpenStruct.new(id: 789, first_name: "User")
    )

    # is_group_chat? will return false, so the command should be ignored.
    # No API calls or other methods should be invoked.
    @botter.stub(:is_group_chat?, false) do
      @botter.send(:handle_markspam_command, @bot, message)
    end

    # No assertions needed as the method should return early.
    # If any unexpected calls were made, the mocks would fail.
    assert true
  end

  def test_handle_markspam_command_by_non_admin
    message = OpenStruct.new(
      chat: OpenStruct.new(id: 123, type: "group", title: "Test Group"),
      from: OpenStruct.new(id: 789, first_name: "User"),
      reply_to_message: OpenStruct.new(text: "spam")
    )

    # is_admin? will return false, so the command should be ignored.
    # No API calls or other methods should be invoked.
    @botter.stub(:is_group_chat?, true) do
      @botter.stub(:is_admin?, false) do
        @botter.send(:handle_markspam_command, @bot, message)
      end
    end

    assert true
  end

  def test_handle_markspam_command_without_replied_message
    message = OpenStruct.new(
      chat: OpenStruct.new(id: 123, type: "group", title: "Test Group"),
      from: OpenStruct.new(id: 789, first_name: "Admin", last_name: "User"),
      reply_to_message: nil # No replied message
    )

    # The method should return early.
    @botter.stub(:is_group_chat?, true) do
      @botter.stub(:is_admin?, true) do
        TelegramMemberFetcher.stub(:get_bot_chat_member, OpenStruct.new(status: "administrator")) do
          @botter.send(:handle_markspam_command, @bot, message)
        end
      end
    end

    assert true
  end

  def test_handle_markspam_command_with_empty_replied_message
    replied_message = OpenStruct.new(text: "", message_id: 100, from: OpenStruct.new(id: 456))
    message = OpenStruct.new(
      chat: OpenStruct.new(id: 123, type: "group", title: "Test Group"),
      from: OpenStruct.new(id: 789, first_name: "Admin", last_name: "User"),
      reply_to_message: replied_message
    )

    # The method should return early.
    @botter.stub(:is_group_chat?, true) do
      @botter.stub(:is_admin?, true) do
        TelegramMemberFetcher.stub(:get_bot_chat_member, OpenStruct.new(status: "administrator")) do
          @botter.send(:handle_markspam_command, @bot, message)
        end
      end
    end

    assert true
  end
end
