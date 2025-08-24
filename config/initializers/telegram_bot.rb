require 'telegram/bot'

Rails.application.config.after_initialize do
  TelegramBotWorkerJob.perform_later(Rails.application.credentials.dig(:telegram_bot_token))
end

