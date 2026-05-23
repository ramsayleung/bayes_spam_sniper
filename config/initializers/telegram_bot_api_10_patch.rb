# TODO: Remove this patch once telegram-bot-ruby is updated to support Telegram Bot API 10.0
# The `telegram-bot-ruby` gem currently drops unsupported fields. This monkey-patch
# ensures that `guest_bot_caller_user`, `guest_bot_caller_chat`, `guest_query_id` and `guest_message`
# are retained during JSON parsing.

require "telegram/bot"

Rails.application.config.to_prepare do
  class Telegram::Bot::Types::Message < Telegram::Bot::Types::Base
    attribute? :guest_bot_caller_user, Telegram::Bot::Types::User.optional.meta(omittable: true)
    attribute? :guest_bot_caller_chat, Telegram::Bot::Types::Chat.optional.meta(omittable: true)
    attribute? :guest_query_id, Telegram::Bot::Types::String.optional.meta(omittable: true)
  end

  class Telegram::Bot::Types::Update < Telegram::Bot::Types::Base
    attribute? :guest_message, Telegram::Bot::Types::Message.optional.meta(omittable: true)
  end
end
