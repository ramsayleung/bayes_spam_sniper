require 'telegram/bot'

class TelegramBotter
  def start_bot(token)
   
    Telegram::Bot::Client.run(token) do |bot|
      Rails.application.config.telegram_bot = bot
      bot.api.get_updates(offset: -1)

      bot.listen do |message|
        puts "Received message: #{message}"
        if message.text.start_with?("/start")
          bot.api.send_message(chat_id: message.chat.id, text: "Hello, #{message.from.first_name} | Chat ID: #{message.chat.id}")
        else if message.text.start_with?("/stop")
               bot.api.send_message(chat_id: message.chat.id, text: "Bye, #{message.from.first_name} | Chat ID: #{message.chat.id}")
             end
        end
      end
      rescue Telegram::Bot::Exceptions::ResponseError => e
        Rails.logger.error e
        Rails.application.config.telegram_bot.stop
        Rails.application.config.telegram_bot.api.delete_webhook
    end
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
end
