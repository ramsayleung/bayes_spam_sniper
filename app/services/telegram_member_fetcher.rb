require "telegram/bot"

class TelegramMemberFetcher
  def self.get_bot_chat_member(group_id)
    bot_id = Rails.cache.fetch("bot_id", expires_in: 24.hours) do
      bot.api.get_me.id
    end
    get_chat_member(group_id, bot_id)
  end

  def self.get_chat_member(group_id, user_id)
    cache_key = "#{group_id}_#{user_id}_group_chat_member"
    chat_member = Rails.cache.fetch(cache_key, expires_in: 1.hours) do
      begin
        bot.api.get_chat_member(chat_id: group_id, user_id: user_id)
      rescue => e
        Rails.logger.error "Error getting member for group #{group_id}: #{e.message}"
        nil
      end
    end
  end

  private
  def self.bot
    @bot ||= Telegram::Bot::Client.new(Rails.application.credentials.dig(:telegram_bot_token))
  end
end
