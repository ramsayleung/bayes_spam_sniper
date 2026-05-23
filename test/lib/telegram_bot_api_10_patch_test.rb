require "test_helper"
require "telegram/bot"

class TelegramBotApi10PatchTest < ActiveSupport::TestCase
  def test_message_parses_guest_bot_caller_user_correctly
    raw_json = {
      "message_id" => 752,
      "date" => 1779512696,
      "chat" => {
        "id" => -1003098822405,
        "type" => "supergroup",
        "title" => "DevBSS Testing"
      },
      "guest_bot_caller_user" => {
        "id" => 8815951945,
        "is_bot" => true,
        "first_name" => "Recommendation",
        "username" => "cy6abot"
      },
      "guest_query_id" => "query123",
      "text" => "Spam text here"
    }

    message = Telegram::Bot::Types::Message.new(raw_json)

    assert_not_nil message.guest_bot_caller_user
    assert_equal 8815951945, message.guest_bot_caller_user.id
    assert_equal "cy6abot", message.guest_bot_caller_user.username
    assert_equal "query123", message.guest_query_id

    hash_representation = message.to_h
    assert_not_nil hash_representation[:guest_bot_caller_user]
    assert_equal 8815951945, hash_representation[:guest_bot_caller_user][:id]
  end

  def test_update_parses_guest_message_correctly
    raw_json = {
      "update_id" => 12345,
      "guest_message" => {
        "message_id" => 752,
        "date" => 1779512696,
        "chat" => {
          "id" => -1003098822405,
          "type" => "supergroup"
        },
        "text" => "Guest text"
      }
    }

    update = Telegram::Bot::Types::Update.new(raw_json)

    assert_not_nil update.guest_message
    assert_equal 752, update.guest_message.message_id
    assert_equal "Guest text", update.guest_message.text
  end
end
