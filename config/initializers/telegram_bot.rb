require "telegram/bot"

# Set up the telegram bot configuration for all Rails processes
Rails.application.configure do
  token = Rails.application.credentials.dig(:telegram_bot_token)
  if token
    config.telegram_bot = Telegram::Bot::Client.new(token)
  else
    Rails.logger.warn "Telegram bot token not found in credentials"
  end
end
