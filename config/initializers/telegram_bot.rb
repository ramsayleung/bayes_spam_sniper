require 'telegram/bot'

Rails.application.config.after_initialize do
  token = Rails.application.credentials.dig(:telegram_bot_token)

  Telegram::Bot::Client.run(token) do |bot|
    Rails.application.config.telegram_bot = bot

    bot.listen do |message|
      next unless message.is_a?(Telegram::Bot::Types::Message)
      case message.text
      when '/start'
        bot.api.send_message(chat_id: message.chat.id, text: "Hello, #{message.from.first_name} | Chat ID: #{message.chat.id}")
      when '/stop'
        bot.api.send_message(chat_id: message.chat.id, text: "Bye, #{message.from.first_name} | Chat ID: #{message.chat.id}")
      end
    end
  end
  rescue Telegram::Bot::Exceptions::ResponseError => e
    Rails.logger.error e
    Rails.application.config.telegram_bot.stop
    Rails.application.config.telegram_bot.api.delete_webhook
end

Signal.trap("TERM") do
  puts "Shutting down bot..."
  Rails.application.config.telegram_bot.stop
  exit
end

Signal.trap("INT") do
  puts "Shutting down bot..."
  Rails.application.config.telegram_bot.stop
  exit
end
