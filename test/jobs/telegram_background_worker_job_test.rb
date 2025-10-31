require "test_helper"
require "ostruct"
require "minitest/mock"

class TelegramBackgroundWorkerJobTest < ActiveJob::TestCase
  setup do
    # Setup test data
    @group_id = 12345
    @group_name = "Test Group"
    @user_id = 67890
    @user_name = "TestSpammer"
    @message = "spam message"
    @message_id = 111

    @trained_message_data = {
      group_id: @group_id,
      group_name: @group_name,
      sender_chat_id: @user_id,
      sender_user_name: @user_name,
      message: @message,
      message_id: @message_id
    }

    # Mock chat member with admin permissions
    @chat_member = OpenStruct.new(
      status: "administrator",
      can_restrict_members: true
    )
  end

  test "ban_user action bans user in single group" do
    TelegramMemberFetcher.stub(:get_bot_chat_member, @chat_member) do
      api_mock = Minitest::Mock.new

      mock_sent_message = OpenStruct.new(
        chat: OpenStruct.new(id: @group_id),
        message_id: 999999999
      )

      # For keyword arguments, pass as a single hash
      # The mock will receive: ban_chat_member(chat_id: @group_id, user_id: @user_id)
      api_mock.expect(:ban_chat_member, nil) do |**kwargs|
        kwargs[:chat_id] == @group_id && kwargs[:user_id] == @user_id
      end

      api_mock.expect(:send_message, mock_sent_message) do |**kwargs|
        kwargs[:chat_id] == @group_id &&
        kwargs[:text].is_a?(String) &&
          kwargs[:parse_mode] == "Markdown"
      end

      # Stub the bot client
      bot_client_stub = ->(_token) {
        OpenStruct.new(api: api_mock)
      }

      Telegram::Bot::Client.stub(:new, bot_client_stub) do
        TelegramBackgroundWorkerJob.perform_now(
          action: PostAction::BAN_USER,
          trained_message_data: @trained_message_data
        )
      end

      # Verify all expectations were met
      api_mock.verify

      # Verify BannedUser was created
      banned_user = BannedUser.find_by(group_id: @group_id, sender_chat_id: @user_id)
      assert_not_nil banned_user
      assert_equal @group_name, banned_user.group_name
      assert_equal @user_name, banned_user.sender_user_name
      assert_equal @message, banned_user.spam_message
      assert_equal @message_id, banned_user.message_id
    end
  end

  test "global_ban_user action bans user in multiple groups" do
    # Clear fixture data
    GroupClassifierState.delete_all

    # Setup multiple groups
    group1_id = 11111
    group1_name = "Group 1"
    group2_id = 22222
    group2_name = "Group 2"
    group3_id = 33333
    group3_name = "Group 3"

    GroupClassifierState.create!(group_id: group1_id, group_name: group1_name)
    GroupClassifierState.create!(group_id: group2_id, group_name: group2_name)
    GroupClassifierState.create!(group_id: group3_id, group_name: group3_name)

    TelegramMemberFetcher.stub(:get_bot_chat_member, @chat_member) do
      api_mock = Minitest::Mock.new

      # Expect ban_chat_member for each group
      banned_groups = []
      4.times do
        api_mock.expect(:ban_chat_member, nil) do |**kwargs|
          banned_groups << kwargs[:chat_id]
          [ group1_id, group2_id, group3_id, @group_id ].include?(kwargs[:chat_id]) &&
            kwargs[:user_id] == @user_id
        end
      end

      mock_sent_message = OpenStruct.new(
        chat: OpenStruct.new(id: @group_id),
        message_id: 999999999
      )
      # Expect notification to each group for global ban (4 total groups)
      4.times do
        api_mock.expect(:send_message, mock_sent_message) do |**kwargs|
          [ group1_id, group2_id, group3_id, @group_id ].include?(kwargs[:chat_id]) &&
            kwargs[:parse_mode] == "Markdown"
        end
      end

      bot_client_stub = ->(_token) {
        OpenStruct.new(api: api_mock)
      }

      Telegram::Bot::Client.stub(:new, bot_client_stub) do
        TelegramBackgroundWorkerJob.perform_now(
          action: PostAction::GLOBAL_BAN_USER,
          trained_message_data: @trained_message_data
        )
      end

      api_mock.verify

      # Verify all groups were banned
      assert_equal 4, banned_groups.uniq.length

      # Verify BannedUser was created for each group
      assert_equal 4, BannedUser.where(sender_chat_id: @user_id).count

      banned_user1 = BannedUser.find_by(group_id: group1_id, sender_chat_id: @user_id)
      assert_not_nil banned_user1
      assert_equal group1_name, banned_user1.group_name
    end
  end

  test "skips banning when bot has insufficient permissions" do
    chat_member_no_perms = OpenStruct.new(
      status: "administrator",
      can_restrict_members: false
    )

    TelegramMemberFetcher.stub(:get_bot_chat_member, chat_member_no_perms) do
      api_mock = Minitest::Mock.new

      # Should NOT call ban_chat_member
      bot_client_stub = ->(_token) {
        OpenStruct.new(api: api_mock)
      }

      Telegram::Bot::Client.stub(:new, bot_client_stub) do
        TelegramBackgroundWorkerJob.perform_now(
          action: PostAction::BAN_USER,
          trained_message_data: @trained_message_data
        )
      end

      api_mock.verify

      # Verify BannedUser was NOT created
      assert_nil BannedUser.find_by(group_id: @group_id, sender_chat_id: @user_id)
    end
  end

  test "skips banning in data collector groups" do
    @trained_message_data[:group_id] = GroupClassifierState::TELEGRAM_DATA_COLLECTOR_GROUP_ID

    TelegramMemberFetcher.stub(:get_bot_chat_member, @chat_member) do
      api_mock = Minitest::Mock.new

      bot_client_stub = ->(_token) {
        OpenStruct.new(api: api_mock)
      }

      Telegram::Bot::Client.stub(:new, bot_client_stub) do
        TelegramBackgroundWorkerJob.perform_now(
          action: PostAction::BAN_USER,
          trained_message_data: @trained_message_data
        )
      end

      api_mock.verify

      # Verify BannedUser was NOT created
      assert_nil BannedUser.find_by(
                   group_id: GroupClassifierState::TELEGRAM_DATA_COLLECTOR_GROUP_ID,
                   sender_chat_id: @user_id
                 )
    end
  end

  test "skips banning when user_id is 0" do
    @trained_message_data[:sender_chat_id] = 0

    TelegramMemberFetcher.stub(:get_bot_chat_member, @chat_member) do
      api_mock = Minitest::Mock.new

      bot_client_stub = ->(_token) {
        OpenStruct.new(api: api_mock)
      }

      Telegram::Bot::Client.stub(:new, bot_client_stub) do
        TelegramBackgroundWorkerJob.perform_now(
          action: PostAction::BAN_USER,
          trained_message_data: @trained_message_data
        )
      end

      api_mock.verify

      # Verify BannedUser was NOT created
      assert_nil BannedUser.find_by(sender_chat_id: 0)
    end
  end

  test "handles Telegram API errors gracefully" do
    TelegramMemberFetcher.stub(:get_bot_chat_member, @chat_member) do
      api_mock = Minitest::Mock.new

      # Simulate API error on ban_chat_member
      api_mock.expect(:ban_chat_member, nil) do |**kwargs|
        mock_response = OpenStruct.new(
          body: '{"ok":false,"error_code":400,"description":"Bad Request: user not found"}',
          status: 400,
          env: OpenStruct.new(url: "https://api.telegram.org/botTOKEN/banChatMember")
        )
        raise Telegram::Bot::Exceptions::ResponseError.new(response: mock_response)
      end

      bot_client_stub = ->(_token) {
        OpenStruct.new(api: api_mock)
      }

      Telegram::Bot::Client.stub(:new, bot_client_stub) do
        assert_nothing_raised do
          TelegramBackgroundWorkerJob.perform_now(
            action: PostAction::BAN_USER,
            trained_message_data: @trained_message_data
          )
        end
      end

      api_mock.verify

      # BannedUser should NOT be created due to error
      assert_nil BannedUser.find_by(group_id: @group_id, sender_chat_id: @user_id)
    end
  end
end
